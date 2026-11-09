/* Tiempos invertidos: reporte dinámico de worklogs con una columna por periodo y agrupaciones elegibles (como el
   reporte "Worklogs" de Jira). Filas en árbol: Total → categoría → grupo → agrupación secundaria, cada una con su
   subtotal; columnas: Total y una por periodo (día, semana, mes, trimestre o año), incluidos los periodos sin tiempo.
   Celda vacía = sin tiempo.
   - Tiempo que cuenta: el registrado por personas y el automático real; NO las copias de Automation for Jira (ese
     trabajo ya está en el original). La persona es a quien se atribuye el worklog (como en Horas por persona).
   - Filtros: fechas del worklog, proyectos y personas (varios, separados por '|'), sprint (sus issues, y solo el tiempo
     registrado entre su inicio y su cierre).
   - Agrupaciones (@Categoria, @Grupo, @Secundaria): persona | proyecto | epica | tarea (las subtareas se suman en su
     tarea) | issue | tipo | estado | ninguna. Si dos niveles piden lo mismo, se usa una vez.
   - Unidad: horas, o días de @HorasPorDia horas (8, como Jira por omisión).
   Las columnas de periodo dependen del filtro (SQL dinámico); como mucho 120 (si no, se pide agrupar por un periodo
   más largo). */
CREATE OR ALTER PROCEDURE api.Tiempos_Invertidos
    @Desde       date,
    @Hasta       date,
    @Proyecto    nvarchar(1000) = NULL,     -- claves separadas por '|'
    @Persona     nvarchar(2000) = NULL,     -- nombres separados por '|'
    @Sprint      nvarchar(255) = NULL,      -- nombre del sprint
    @Periodo     varchar(10) = 'mes',       -- dia | semana | mes | trimestre | anio | ninguno
    @Categoria   varchar(10) = 'persona',
    @Grupo       varchar(10) = 'issue',
    @Secundaria  varchar(10) = 'ninguna',
    @Unidad      varchar(5) = 'horas',      -- horas | dias
    @HorasPorDia decimal(4,1) = 8
AS
BEGIN
    SET NOCOUNT ON;
    SET @Periodo = ISNULL(NULLIF(@Periodo, ''), 'mes');
    SET @Categoria = ISNULL(NULLIF(@Categoria, ''), 'persona');
    SET @Grupo = ISNULL(NULLIF(@Grupo, ''), 'issue');
    SET @Secundaria = ISNULL(NULLIF(@Secundaria, ''), 'ninguna');
    SET @Unidad = ISNULL(NULLIF(@Unidad, ''), 'horas');
    IF ISNULL(@HorasPorDia, 0) <= 0 SET @HorasPorDia = 8;
    IF @Desde > @Hasta THROW 50400, 'La fecha inicial es posterior a la final.', 1;
    IF @Periodo NOT IN ('dia', 'semana', 'mes', 'trimestre', 'anio', 'ninguno') THROW 50400, 'Periodo no válido: dia, semana, mes, trimestre, anio o ninguno.', 1;
    IF EXISTS (SELECT 1 FROM (VALUES (@Categoria), (@Grupo), (@Secundaria)) x (d)
               WHERE d NOT IN ('persona', 'proyecto', 'epica', 'tarea', 'issue', 'tipo', 'estado', 'ninguna'))
        THROW 50400, 'Agrupación no válida: persona, proyecto, epica, tarea, issue, tipo, estado o ninguna.', 1;
    IF @Unidad NOT IN ('horas', 'dias') THROW 50400, 'Unidad debe ser horas o dias.', 1;

    -- Niveles que se usan, en orden, sin "ninguna" ni repetidos.
    DECLARE @dim TABLE (Nivel int PRIMARY KEY, Dim varchar(10));
    INSERT @dim SELECT ROW_NUMBER() OVER (ORDER BY MIN(o)), d
    FROM (VALUES (1, @Categoria), (2, @Grupo), (3, @Secundaria)) x (o, d) WHERE d <> 'ninguna' GROUP BY d;
    DECLARE @d1 varchar(10) = (SELECT Dim FROM @dim WHERE Nivel = 1),
            @d2 varchar(10) = (SELECT Dim FROM @dim WHERE Nivel = 2),
            @d3 varchar(10) = (SELECT Dim FROM @dim WHERE Nivel = 3);

    -- Periodos del rango (columnas), con su nombre.
    DECLARE @div decimal(12,4) = CASE WHEN @Unidad = 'dias' THEN 3600.0 * @HorasPorDia ELSE 3600.0 END;
    CREATE TABLE #p (Per date PRIMARY KEY, Col nvarchar(40) NOT NULL, Orden int NOT NULL);
    IF @Periodo <> 'ninguno'
    BEGIN
        DECLARE @meses TABLE (M int PRIMARY KEY, N nvarchar(3));
        INSERT @meses VALUES (1, N'Ene'), (2, N'Feb'), (3, N'Mar'), (4, N'Abr'), (5, N'May'), (6, N'Jun'),
                             (7, N'Jul'), (8, N'Ago'), (9, N'Sep'), (10, N'Oct'), (11, N'Nov'), (12, N'Dic');
        WITH dias AS (
            SELECT @Desde AS F UNION ALL SELECT DATEADD(DAY, 1, F) FROM dias WHERE F < @Hasta
        ), per AS (
            SELECT DISTINCT CASE @Periodo
                     WHEN 'dia' THEN F
                     WHEN 'semana' THEN DATEADD(DAY, -((DATEPART(WEEKDAY, F) + @@DATEFIRST - 2) % 7), F)   -- lunes
                     WHEN 'mes' THEN DATEFROMPARTS(YEAR(F), MONTH(F), 1)
                     WHEN 'trimestre' THEN DATEFROMPARTS(YEAR(F), (DATEPART(QUARTER, F) - 1) * 3 + 1, 1)
                     ELSE DATEFROMPARTS(YEAR(F), 1, 1) END AS Per
            FROM dias
        )
        INSERT #p (Per, Col, Orden)
        SELECT p.Per,
               CASE @Periodo
                 WHEN 'dia' THEN CONCAT(CHOOSE((DATEPART(WEEKDAY, p.Per) + @@DATEFIRST - 2) % 7 + 1, N'Lun', N'Mar', N'Mié', N'Jue', N'Vie', N'Sáb', N'Dom'),
                                        N' ', CONVERT(nvarchar(8), p.Per, 3))
                 WHEN 'semana' THEN CONCAT(N'Sem ', CONVERT(nvarchar(8), p.Per, 3))
                 WHEN 'mes' THEN CONCAT(m.N, N' ', YEAR(p.Per))
                 WHEN 'trimestre' THEN CONCAT(N'T', DATEPART(QUARTER, p.Per), N' ', YEAR(p.Per))
                 ELSE CAST(YEAR(p.Per) AS nvarchar(4)) END,
               ROW_NUMBER() OVER (ORDER BY p.Per)
        FROM per p JOIN @meses m ON m.M = MONTH(p.Per)
        OPTION (MAXRECURSION 0);
        IF (SELECT COUNT(*) FROM #p) > 120
            THROW 50400, 'Son más de 120 columnas: agrupe por un periodo más largo (semana, mes…) o acorte las fechas.', 1;
    END;

    DECLARE @proyectos TABLE (Clave varchar(50) PRIMARY KEY);
    INSERT @proyectos SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Proyecto, '|') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @personas TABLE (Nombre nvarchar(255) PRIMARY KEY);
    INSERT @personas SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Persona, '|') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @hayProyectos bit = CASE WHEN EXISTS (SELECT 1 FROM @proyectos) THEN 1 ELSE 0 END,
            @hayPersonas bit = CASE WHEN EXISTS (SELECT 1 FROM @personas) THEN 1 ELSE 0 END;

    -- Sprint: sus issues y su ventana (del inicio al cierre; si sigue activo, sin fin).
    DECLARE @ventana TABLE (FuenteId int, SprintId bigint, Inicio datetimeoffset(3), Fin datetimeoffset(3));
    IF @Sprint IS NOT NULL
    BEGIN
        INSERT @ventana SELECT s.FuenteId, s.SprintId, s.Inicio, COALESCE(s.Completado, CASE WHEN s.Estado = 'active' THEN NULL ELSE s.Fin END)
        FROM ops.Sprint s WHERE s.Nombre = @Sprint;
        IF NOT EXISTS (SELECT 1 FROM @ventana) THROW 50404, 'No hay un sprint con ese nombre.', 1;
    END;

    -- Worklogs del filtro, con su periodo y sus agrupaciones.
    SELECT w.Segundos,
           CASE @Periodo WHEN 'dia' THEN w.Fecha
                         WHEN 'semana' THEN DATEADD(DAY, -((DATEPART(WEEKDAY, w.Fecha) + @@DATEFIRST - 2) % 7), w.Fecha)
                         WHEN 'mes' THEN DATEFROMPARTS(YEAR(w.Fecha), MONTH(w.Fecha), 1)
                         WHEN 'trimestre' THEN DATEFROMPARTS(YEAR(w.Fecha), (DATEPART(QUARTER, w.Fecha) - 1) * 3 + 1, 1)
                         WHEN 'anio' THEN DATEFROMPARTS(YEAR(w.Fecha), 1, 1) END AS Per,
           a.Llave AS L1, a.Clave AS C1, a.Texto AS T1, a.Orden AS O1,
           b.Llave AS L2, b.Clave AS C2, b.Texto AS T2, b.Orden AS O2,
           c.Llave AS L3, c.Clave AS C3, c.Texto AS T3, c.Orden AS O3
    INTO #d
    FROM rpt.vWorklog w
    JOIN rpt.vIssue i ON i.IssueSk = w.IssueSk
    LEFT JOIN rpt.vIssue t ON i.NivelJerarquia < 0 AND t.FuenteId = i.FuenteId AND t.IssueId = i.PadreId
    LEFT JOIN ops.Issue ep ON ep.FuenteId = i.FuenteId AND ep.IssueId = i.EpicaIssueId
    CROSS APPLY (SELECT COALESCE(t.Clave, i.Clave) AS TareaClave, COALESCE(t.Resumen, i.Resumen) AS TareaResumen) tt
    OUTER APPLY rpt.fn_TiemposDimension(@d1, w.AtribuidoA, i.ProyectoClave, i.ProyectoNombre, i.EpicaClave, ep.Resumen,
                                        tt.TareaClave, tt.TareaResumen, i.Clave, i.Resumen, i.TipoIssue, i.Estado) a
    OUTER APPLY rpt.fn_TiemposDimension(@d2, w.AtribuidoA, i.ProyectoClave, i.ProyectoNombre, i.EpicaClave, ep.Resumen,
                                        tt.TareaClave, tt.TareaResumen, i.Clave, i.Resumen, i.TipoIssue, i.Estado) b
    OUTER APPLY rpt.fn_TiemposDimension(@d3, w.AtribuidoA, i.ProyectoClave, i.ProyectoNombre, i.EpicaClave, ep.Resumen,
                                        tt.TareaClave, tt.TareaResumen, i.Clave, i.Resumen, i.TipoIssue, i.Estado) c
    WHERE w.Origen <> 'copia'
      AND w.Fecha BETWEEN @Desde AND @Hasta
      AND w.Inicio >= DATEADD(DAY, -1, CAST(@Desde AS datetimeoffset(3))) AND w.Inicio < DATEADD(DAY, 2, CAST(@Hasta AS datetimeoffset(3)))
      AND (@hayProyectos = 0 OR i.ProyectoClave IN (SELECT Clave FROM @proyectos))
      AND (@hayPersonas = 0 OR w.AtribuidoA IN (SELECT Nombre FROM @personas))
      AND (@Sprint IS NULL OR EXISTS (
            SELECT 1 FROM @ventana s JOIN ops.IssueSprint x ON x.FuenteId = s.FuenteId AND x.SprintId = s.SprintId
            WHERE x.IssueSk = i.IssueSk AND (s.Inicio IS NULL OR w.Inicio >= s.Inicio) AND (s.Fin IS NULL OR w.Inicio <= s.Fin)))
    OPTION (RECOMPILE);

    -- Número corto por valor de cada nivel (para Nodo).
    SELECT d.*, DENSE_RANK() OVER (ORDER BY d.L1) AS R1, DENSE_RANK() OVER (ORDER BY d.L2) AS R2, DENSE_RANK() OVER (ORDER BY d.L3) AS R3
    INTO #r FROM #d d;

    -- Subtotales: por nodo y periodo (Per) y por nodo (Per NULL = columna Total).
    SELECT CASE WHEN GROUPING(R1) = 1 THEN 0 WHEN GROUPING(R2) = 1 THEN 1 WHEN GROUPING(R3) = 1 THEN 2 ELSE 3 END AS Nivel,
           R1, R2, R3, CASE WHEN GROUPING(Per) = 1 THEN NULL ELSE Per END AS Per, SUM(CAST(Segundos AS bigint)) AS Seg
    INTO #v
    FROM #r
    GROUP BY GROUPING SETS ((R1, R2, R3, Per), (R1, R2, R3), (R1, R2, Per), (R1, R2), (R1, Per), (R1), (Per), ());

    -- Nodos (filas del árbol).
    CREATE TABLE #n (Nodo nvarchar(60) NOT NULL PRIMARY KEY, PadreNodo nvarchar(60) NULL, Nivel int NOT NULL, NivelNombre nvarchar(30) NULL,
                     Clave varchar(50) NULL, Elemento nvarchar(400) NULL, Ruta varchar(100) NOT NULL);
    DECLARE @nombre1 nvarchar(30) = CASE @d1 WHEN 'persona' THEN N'Persona' WHEN 'proyecto' THEN N'Proyecto' WHEN 'epica' THEN N'Épica' WHEN 'tarea' THEN N'Tarea' WHEN 'issue' THEN N'Ticket' WHEN 'tipo' THEN N'Tipo' WHEN 'estado' THEN N'Estado' END,
            @nombre2 nvarchar(30) = CASE @d2 WHEN 'persona' THEN N'Persona' WHEN 'proyecto' THEN N'Proyecto' WHEN 'epica' THEN N'Épica' WHEN 'tarea' THEN N'Tarea' WHEN 'issue' THEN N'Ticket' WHEN 'tipo' THEN N'Tipo' WHEN 'estado' THEN N'Estado' END,
            @nombre3 nvarchar(30) = CASE @d3 WHEN 'persona' THEN N'Persona' WHEN 'proyecto' THEN N'Proyecto' WHEN 'epica' THEN N'Épica' WHEN 'tarea' THEN N'Tarea' WHEN 'issue' THEN N'Ticket' WHEN 'tipo' THEN N'Tipo' WHEN 'estado' THEN N'Estado' END;
    INSERT #n VALUES (N'#total', NULL, 0, N'Total',  NULL,
                      CONCAT(N'Total en ', CASE WHEN @Unidad = 'dias' THEN CONCAT(N'días de ', FORMAT(@HorasPorDia, '0.#'), N' h') ELSE N'horas' END,
                             N' · ', CONVERT(nvarchar(10), @Desde, 103), N' al ', CONVERT(nvarchar(10), @Hasta, 103)), '');
    IF @d1 IS NOT NULL
    BEGIN
        SELECT R1, MIN(C1) AS C, MIN(T1) AS T, MIN(O1) AS O INTO #k1 FROM #r GROUP BY R1;
        INSERT #n SELECT CONCAT(N'a', R1), N'#total', 1, @nombre1, C, T,
                         RIGHT('00000' + CAST(ROW_NUMBER() OVER (ORDER BY O, R1) AS varchar(6)), 6) FROM #k1;
    END;
    IF @d2 IS NOT NULL
    BEGIN
        SELECT R1, R2, MIN(C2) AS C, MIN(T2) AS T, MIN(O2) AS O INTO #k2 FROM #r GROUP BY R1, R2;
        INSERT #n SELECT CONCAT(N'a', k.R1, N'|b', k.R2), CONCAT(N'a', k.R1), 2, @nombre2, k.C, k.T,
                         p.Ruta + '/' + RIGHT('00000' + CAST(ROW_NUMBER() OVER (PARTITION BY k.R1 ORDER BY k.O, k.R2) AS varchar(6)), 6)
        FROM #k2 k JOIN #n p ON p.Nodo = CONCAT(N'a', k.R1);
    END;
    IF @d3 IS NOT NULL
    BEGIN
        SELECT R1, R2, R3, MIN(C3) AS C, MIN(T3) AS T, MIN(O3) AS O INTO #k3 FROM #r GROUP BY R1, R2, R3;
        INSERT #n SELECT CONCAT(N'a', k.R1, N'|b', k.R2, N'|c', k.R3), CONCAT(N'a', k.R1, N'|b', k.R2), 3, @nombre3, k.C, k.T,
                         p.Ruta + '/' + RIGHT('00000' + CAST(ROW_NUMBER() OVER (PARTITION BY k.R1, k.R2 ORDER BY k.O, k.R3) AS varchar(6)), 6)
        FROM #k3 k JOIN #n p ON p.Nodo = CONCAT(N'a', k.R1, N'|b', k.R2);
    END;

    -- Valor de cada celda: nodo × periodo, en la unidad pedida.
    SELECT CASE v.Nivel WHEN 0 THEN N'#total' WHEN 1 THEN CONCAT(N'a', v.R1) WHEN 2 THEN CONCAT(N'a', v.R1, N'|b', v.R2)
                ELSE CONCAT(N'a', v.R1, N'|b', v.R2, N'|c', v.R3) END AS Nodo,
           ISNULL(p.Col, N'Total') AS Col,
           CAST(v.Seg / @div AS decimal(12,2)) AS Valor
    INTO #c
    FROM #v v LEFT JOIN #p p ON p.Per = v.Per
    WHERE v.Nivel = 0 OR (v.Nivel = 1 AND @d1 IS NOT NULL) OR (v.Nivel = 2 AND @d2 IS NOT NULL) OR (v.Nivel = 3 AND @d3 IS NOT NULL);

    -- Una columna por periodo (los nombres salen de #p: QUOTENAME evita inyección).
    DECLARE @cols nvarchar(max) = (SELECT STRING_AGG(CAST(QUOTENAME(Col) AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY Orden) FROM #p);
    DECLARE @sql nvarchar(max) = N'
        SELECT n.Nodo, n.PadreNodo, n.Nivel, n.NivelNombre, n.Clave, n.Elemento, x.[Total]' + ISNULL(N', ' + @cols, N'') + N'
        FROM #n n
        LEFT JOIN (SELECT Nodo, Col, Valor FROM #c) s
            PIVOT (SUM(Valor) FOR Col IN ([Total]' + ISNULL(N', ' + @cols, N'') + N')) x ON x.Nodo = n.Nodo
        ORDER BY n.Ruta;';
    EXEC sys.sp_executesql @sql;
END;
GO
