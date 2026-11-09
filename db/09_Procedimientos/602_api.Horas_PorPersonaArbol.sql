/* Horas por persona en jerarquía, con subtotales: Total → persona → proyecto → épica → tarea → subtarea.
   Cada worklog del periodo se atribuye como en api.Horas_PorPersona (rpt.vWorklog: las automáticas al responsable del
   issue ese día) y se suma en su issue y en todos sus antecesores, así cada fila es el subtotal de lo que tiene debajo
   y cada worklog cuenta una sola vez. Las tareas sin épica van en "(Sin épica)" dentro de su proyecto.
   Una fila por nodo: Nodo / PadreNodo / Nivel / NivelNombre arman el árbol en la interfaz. */
CREATE OR ALTER PROCEDURE api.Horas_PorPersonaArbol
    @Desde        date,
    @Hasta        date,
    @Proyecto     varchar(50) = NULL,
    @TipoProyecto varchar(30) = NULL,
    @Origen       varchar(12) = NULL,     -- manual | automatico | NULL = ambos
    @Epica        varchar(50) = NULL,     -- clave de una épica: solo su tiempo (con tareas y subtareas)
    @Persona      nvarchar(200) = NULL    -- parte del nombre de la persona
AS
BEGIN
    SET NOCOUNT ON;
    IF @Origen IS NOT NULL AND @Origen NOT IN ('manual', 'automatico')
        THROW 50400, 'Origen debe ser manual o automatico.', 1;

    -- 1. Horas propias por persona e issue en el periodo.
    SELECT w.AtribuidoA AS Persona, w.FuenteId, w.IssueId, w.ProyectoClave,
           SUM(CASE WHEN w.Origen = 'manual' THEN CAST(w.Segundos AS bigint) ELSE 0 END) AS SegReg,
           SUM(CASE WHEN w.Origen = 'automatico' THEN CAST(w.Segundos AS bigint) ELSE 0 END) AS SegAut
    INTO #h
    FROM rpt.vWorklog w
    WHERE w.Fecha BETWEEN @Desde AND @Hasta
      AND w.Inicio >= DATEADD(DAY, -1, CAST(@Desde AS datetimeoffset(3))) AND w.Inicio < DATEADD(DAY, 2, CAST(@Hasta AS datetimeoffset(3)))
      AND (@Proyecto IS NULL OR w.ProyectoClave = @Proyecto)
      AND (@TipoProyecto IS NULL OR w.TipoProyecto = @TipoProyecto)
      AND (@Origen IS NULL OR w.Origen = @Origen) AND w.Origen <> 'copia'   -- las copias automáticas no se suman
      AND (@Persona IS NULL OR w.AtribuidoA LIKE N'%' + @Persona + N'%')
    GROUP BY w.AtribuidoA, w.FuenteId, w.IssueId, w.ProyectoClave
    OPTION (RECOMPILE);

    -- 2. Antecesores de cada issue con horas (él mismo, su padre, su abuelo…), hasta la épica.
    WITH sube AS (
        SELECT DISTINCT h.FuenteId, h.IssueId AS Base, h.IssueId AS Anc, 0 AS D FROM #h h
        UNION ALL
        SELECT s.FuenteId, s.Base, p.IssueId, s.D + 1
        FROM sube s
        JOIN ops.Issue i ON i.FuenteId = s.FuenteId AND i.IssueId = s.Anc
        JOIN ops.Issue p ON p.FuenteId = i.FuenteId AND p.IssueId = i.PadreId AND p.Eliminado = 0
        WHERE s.D < 5
    )
    SELECT FuenteId, Base, Anc, D INTO #anc FROM sube OPTION (MAXRECURSION 10);

    IF @Epica IS NOT NULL
    BEGIN
        -- Solo el tiempo de la épica pedida: issues que la tienen como antecesor (o son ella).
        DELETE h FROM #h h
        WHERE NOT EXISTS (SELECT 1 FROM #anc a JOIN ops.Issue e ON e.FuenteId = a.FuenteId AND e.IssueId = a.Anc
                          WHERE a.FuenteId = h.FuenteId AND a.Base = h.IssueId AND e.Clave = @Epica);
    END;

    -- Raíz de cada issue con horas (el antecesor más lejano) y su profundidad bajo la raíz.
    SELECT a.FuenteId, a.Base, a.Anc AS Raiz, a.D AS Prof
    INTO #raiz
    FROM #anc a
    WHERE a.D = (SELECT MAX(x.D) FROM #anc x WHERE x.FuenteId = a.FuenteId AND x.Base = a.Base);

    -- 3. Nodos de issue por persona: cada antecesor de un issue con horas, con el subtotal de su rama.
    --    Nivel: 3 la raíz si es épica (las tareas sin épica cuelgan de "(Sin épica)", en el nivel 3), y +1 por nivel.
    SELECT h.Persona, h.ProyectoClave, a.FuenteId, a.Anc AS IssueId, r.Raiz,
           SUM(h.SegReg) AS SegReg, SUM(h.SegAut) AS SegAut,
           SUM(CASE WHEN a.D = 0 THEN h.SegReg + h.SegAut ELSE 0 END) AS SegPropios,
           MAX(r.Prof - a.D) AS ProfNodo,
           COUNT(DISTINCT h.IssueId) AS IssuesConHoras
    INTO #n
    FROM #h h
    JOIN #anc a ON a.FuenteId = h.FuenteId AND a.Base = h.IssueId
    JOIN #raiz r ON r.FuenteId = h.FuenteId AND r.Base = h.IssueId
    GROUP BY h.Persona, h.ProyectoClave, a.FuenteId, a.Anc, r.Raiz;

    -- Ruta de orden de cada nodo de issue: los números de las claves de la raíz al nodo (SSM26-9 antes que SSM26-10).
    WITH sube AS (
        SELECT i.FuenteId, i.IssueId, i.PadreId AS Siguiente,
               CAST(RIGHT(CONCAT(N'000000000', ISNULL(TRY_CAST(SUBSTRING(i.Clave, CHARINDEX('-', i.Clave) + 1, 20) AS int), 0)), 9) AS nvarchar(400)) AS Ruta, 0 AS D
        FROM (SELECT DISTINCT FuenteId, IssueId FROM #n) x JOIN ops.Issue i ON i.FuenteId = x.FuenteId AND i.IssueId = x.IssueId
        UNION ALL
        SELECT s.FuenteId, s.IssueId, p.PadreId,
               CAST(CONCAT(RIGHT(CONCAT(N'000000000', ISNULL(TRY_CAST(SUBSTRING(p.Clave, CHARINDEX('-', p.Clave) + 1, 20) AS int), 0)), 9), N'/', s.Ruta) AS nvarchar(400)), s.D + 1
        FROM sube s JOIN ops.Issue p ON p.FuenteId = s.FuenteId AND p.IssueId = s.Siguiente AND p.Eliminado = 0
        WHERE s.D < 5
    )
    SELECT FuenteId, IssueId, Ruta INTO #ruta
    FROM (SELECT FuenteId, IssueId, Ruta, ROW_NUMBER() OVER (PARTITION BY FuenteId, IssueId ORDER BY D DESC) AS rn FROM sube) x
    WHERE rn = 1
    OPTION (MAXRECURSION 10);

    -- Llave numérica de la persona (para nodos estables) y de orden.
    SELECT Persona, DENSE_RANK() OVER (ORDER BY Persona) AS P INTO #p FROM (SELECT DISTINCT Persona FROM #h) x;

    SELECT x.Nodo, x.PadreNodo, x.Nivel, x.NivelNombre, x.Clave, x.Elemento, x.Tipo, x.Estado,
           CAST(x.SegReg / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(x.SegAut / 3600.0 AS decimal(12,2)) AS HorasAutomaticas,
           CAST((x.SegReg + x.SegAut) / 3600.0 AS decimal(12,2)) AS HorasTotales,
           CAST(NULLIF(x.SegPropios, 0) / 3600.0 AS decimal(12,2)) AS HorasPropias,
           x.IssuesConHoras
    FROM (
        SELECT N'#total' AS Nodo, CAST(NULL AS nvarchar(300)) AS PadreNodo, 0 AS Nivel, N'Total' AS NivelNombre,
               CAST(NULL AS varchar(50)) AS Clave, CAST(N'Total del periodo' AS nvarchar(400)) AS Elemento, CAST(NULL AS nvarchar(255)) AS Tipo,
               CAST(NULL AS nvarchar(255)) AS Estado, SUM(SegReg) AS SegReg, SUM(SegAut) AS SegAut, CAST(NULL AS bigint) AS SegPropios,
               COUNT(DISTINCT CONCAT(FuenteId, N'|', IssueId)) AS IssuesConHoras, CAST(N'0' AS nvarchar(400)) AS Ruta
        FROM #h
        HAVING COUNT(*) > 0
        UNION ALL
        -- Persona
        SELECT CONCAT(N'p', p.P), N'#total', 1, N'Persona', NULL, h.Persona, N'Persona', NULL,
               SUM(h.SegReg), SUM(h.SegAut), NULL, COUNT(DISTINCT CONCAT(h.FuenteId, N'|', h.IssueId)),
               CONCAT(N'1/', RIGHT(CONCAT(N'00000', p.P), 5))
        FROM #h h JOIN #p p ON p.Persona = h.Persona
        GROUP BY p.P, h.Persona
        UNION ALL
        -- Proyecto de la persona
        SELECT CONCAT(N'p', p.P, N'|', h.ProyectoClave), CONCAT(N'p', p.P), 2, N'Proyecto', NULL,
               CONCAT(h.ProyectoClave, N' · ', MAX(pr.Nombre)), N'Proyecto', NULL,
               SUM(h.SegReg), SUM(h.SegAut), NULL, COUNT(DISTINCT CONCAT(h.FuenteId, N'|', h.IssueId)),
               CONCAT(N'1/', RIGHT(CONCAT(N'00000', p.P), 5), N'/', h.ProyectoClave)
        FROM #h h JOIN #p p ON p.Persona = h.Persona
        LEFT JOIN ops.Proyecto pr ON pr.FuenteId = h.FuenteId AND pr.Clave = h.ProyectoClave
        GROUP BY p.P, h.ProyectoClave
        UNION ALL
        -- "(Sin épica)": tareas de la persona en el proyecto cuya raíz no es una épica
        SELECT CONCAT(N'p', p.P, N'|', n.ProyectoClave, N'|#sin-epica'), CONCAT(N'p', p.P, N'|', n.ProyectoClave), 3, N'Épica', NULL,
               N'(Sin épica)', N'Agrupador', NULL, SUM(n.SegReg), SUM(n.SegAut), NULL, SUM(n.IssuesConHoras),
               CONCAT(N'1/', RIGHT(CONCAT(N'00000', p.P), 5), N'/', n.ProyectoClave, N'/2')
        FROM #n n JOIN #p p ON p.Persona = n.Persona
        JOIN ops.Issue ri ON ri.FuenteId = n.FuenteId AND ri.IssueId = n.Raiz
        WHERE n.IssueId = n.Raiz AND ri.NivelJerarquia < 1
        GROUP BY p.P, n.ProyectoClave
        UNION ALL
        -- Issues (épicas, tareas, subtareas)
        SELECT CONCAT(N'p', p.P, N'|', n.ProyectoClave, N'|', i.Clave),
               CASE WHEN n.IssueId <> n.Raiz THEN CONCAT(N'p', p.P, N'|', n.ProyectoClave, N'|', pa.Clave)
                    WHEN i.NivelJerarquia >= 1 THEN CONCAT(N'p', p.P, N'|', n.ProyectoClave)
                    ELSE CONCAT(N'p', p.P, N'|', n.ProyectoClave, N'|#sin-epica') END,
               3 + n.ProfNodo + CASE WHEN ri.NivelJerarquia >= 1 THEN 0 ELSE 1 END,
               CASE i.NivelJerarquia WHEN 1 THEN N'Épica' WHEN -1 THEN N'Subtarea' ELSE N'Tarea' END,
               i.Clave, i.Resumen, i.TipoIssue, e.Nombre,
               n.SegReg, n.SegAut, n.SegPropios, n.IssuesConHoras,
               CONCAT(N'1/', RIGHT(CONCAT(N'00000', p.P), 5), N'/', n.ProyectoClave, N'/', CASE WHEN ri.NivelJerarquia >= 1 THEN N'1' ELSE N'2' END,
                      N'/', ru.Ruta)
        FROM #n n JOIN #p p ON p.Persona = n.Persona
        JOIN ops.Issue i ON i.FuenteId = n.FuenteId AND i.IssueId = n.IssueId
        JOIN ops.Issue ri ON ri.FuenteId = n.FuenteId AND ri.IssueId = n.Raiz
        LEFT JOIN ops.Issue pa ON pa.FuenteId = i.FuenteId AND pa.IssueId = i.PadreId
        LEFT JOIN ops.Estado e ON e.FuenteId = i.FuenteId AND e.EstadoId = i.EstadoId
        JOIN #ruta ru ON ru.FuenteId = n.FuenteId AND ru.IssueId = n.IssueId
    ) x
    ORDER BY x.Ruta;
END;
GO
