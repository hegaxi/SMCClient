/* Tiempo por proyecto en jerarquía: Total → proyecto → épicas → tareas → subtareas, con las horas de cada elemento y
   las de todo lo que tiene debajo (cada worklog se cuenta una sola vez). Las tareas sin épica van en "(Sin épica)"
   dentro de su proyecto. Un proyecto (@Proyecto) o todos (opcionalmente de un tipo: @TipoProyecto).
   - Horas registradas por personas y automáticas (Automation for Jira) por separado; se pueden acotar a un periodo
     (fecha del worklog) y a una persona (a quien se atribuye el worklog, como en Horas por persona).
   - HorasCopiadas: copias que Automation for Jira hace de worklogs de otros issues (de la subtarea a su tarea, su épica
     y el ticket de la OC). Se muestran aparte y NO se suman: ese trabajo ya cuenta donde se registró.
   - Estimación sin doble conteo: de cada rama cuenta la estimación original de los elementos más detallados que la
     tienen (si una tarea y sus subtareas están estimadas, cuentan las subtareas).
   - Una fila por elemento: Nodo / PadreNodo / Nivel / NivelNombre arman el árbol en la interfaz (0 total, 1 proyecto,
     2 épica, 3 tarea, 4 subtarea). */
CREATE OR ALTER PROCEDURE api.Horas_Arbol
    @Desde        date = NULL,          -- primero el periodo, como en los demás reportes de tiempo
    @Hasta        date = NULL,
    @Proyecto     varchar(50) = NULL,
    @TipoProyecto varchar(30) = NULL,
    @Persona      nvarchar(200) = NULL,
    @SoloConHoras bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF @Proyecto IS NOT NULL AND NOT EXISTS (SELECT 1 FROM rpt.vIssue WHERE ProyectoClave = @Proyecto)
        THROW 50404, 'El proyecto no existe, no tiene issues o no se sincroniza.', 1;

    SELECT i.IssueSk, i.FuenteId, i.IssueId, i.Clave, i.PadreId, i.NivelJerarquia, i.TipoIssue, i.Resumen, i.Estado,
           i.Abierto, i.Responsable, i.EstimacionOriginalSeg, i.ProyectoClave, i.ProyectoNombre,
           RIGHT(REPLICATE('0', 9) + CAST(ISNULL(TRY_CAST(SUBSTRING(i.Clave, CHARINDEX('-', i.Clave) + 1, 20) AS int), 0) AS varchar(10)), 9) AS Num
    INTO #i
    FROM rpt.vIssue i
    WHERE (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto)
      AND (@TipoProyecto IS NULL OR i.TipoProyecto = @TipoProyecto);
    CREATE UNIQUE CLUSTERED INDEX IX ON #i (FuenteId, IssueId);

    -- Horas propias de cada issue en el periodo / persona.
    SELECT w.FuenteId, w.IssueId,
           SUM(CASE WHEN w.Origen = 'manual' THEN CAST(w.Segundos AS bigint) END) AS SegReg,
           SUM(CASE WHEN w.Origen = 'automatico' THEN CAST(w.Segundos AS bigint) END) AS SegAut,
           SUM(CASE WHEN w.Origen = 'copia' THEN CAST(w.Segundos AS bigint) END) AS SegCop,
           MAX(CASE WHEN w.Origen <> 'copia' THEN w.Inicio END) AS Ultimo
    INTO #h
    FROM rpt.vWorklog w
    WHERE (@Proyecto IS NULL OR w.ProyectoClave = @Proyecto)
      AND (@TipoProyecto IS NULL OR w.TipoProyecto = @TipoProyecto)
      AND (@Desde IS NULL OR w.Fecha >= @Desde)
      AND (@Hasta IS NULL OR w.Fecha <= @Hasta)
      AND (@Persona IS NULL OR w.AtribuidoA LIKE N'%' + @Persona + N'%')
    GROUP BY w.FuenteId, w.IssueId;

    -- Árbol: raíces = issues cuyo padre no está en el mismo proyecto. Las épicas cuelgan de su proyecto; lo demás, de
    -- "(Sin épica)" de su proyecto.
    WITH arbol AS (
        SELECT r.FuenteId, r.IssueId, r.Clave, r.ProyectoClave,
               CAST(CASE WHEN r.NivelJerarquia >= 1 THEN N'P|' ELSE N'S|' END + r.ProyectoClave AS nvarchar(60)) AS PadreNodo,
               CAST(CASE WHEN r.NivelJerarquia >= 1 THEN 2 ELSE 3 END AS int) AS Nivel,
               CAST(LEFT(r.ProyectoClave + SPACE(20), 20) + CASE WHEN r.NivelJerarquia >= 1 THEN '/1/' ELSE '/2/' END + r.Num AS varchar(400)) AS Ruta,
               CAST(NULL AS varchar(30)) AS PadreIssueId
        FROM #i r
        WHERE r.PadreId IS NULL
           OR NOT EXISTS (SELECT 1 FROM #i p WHERE p.FuenteId = r.FuenteId AND p.IssueId = r.PadreId AND p.ProyectoClave = r.ProyectoClave)
        UNION ALL
        SELECT h.FuenteId, h.IssueId, h.Clave, h.ProyectoClave, CAST(a.Clave AS nvarchar(60)), a.Nivel + 1, CAST(a.Ruta + '/' + h.Num AS varchar(400)),
               CAST(a.IssueId AS varchar(30))
        FROM arbol a JOIN #i h ON h.FuenteId = a.FuenteId AND h.PadreId = a.IssueId AND h.ProyectoClave = a.ProyectoClave
        WHERE a.Nivel < 7
    )
    SELECT FuenteId, IssueId, Clave, ProyectoClave, PadreNodo, Nivel, Ruta, PadreIssueId INTO #n FROM arbol OPTION (MAXRECURSION 10);
    CREATE CLUSTERED INDEX IX ON #n (FuenteId, PadreIssueId);

    -- Pares (ancestro, descendiente o él mismo) para sumar cada rama.
    WITH par AS (
        SELECT n.FuenteId, n.IssueId AS Anc, n.IssueId AS Des, 0 AS D FROM #n n
        UNION ALL
        SELECT p.FuenteId, p.Anc, h.IssueId, p.D + 1
        FROM par p JOIN #n h ON h.FuenteId = p.FuenteId AND h.PadreIssueId = p.Des
        WHERE p.D < 6
    )
    SELECT FuenteId, Anc, Des, D INTO #par FROM par OPTION (MAXRECURSION 10);
    CREATE CLUSTERED INDEX IX ON #par (FuenteId, Anc);

    -- Estimación efectiva: la del elemento si nada debajo de él está estimado.
    SELECT i.FuenteId, i.IssueId,
           CASE WHEN i.EstimacionOriginalSeg > 0
                     AND NOT EXISTS (SELECT 1 FROM #par x JOIN #i d ON d.FuenteId = x.FuenteId AND d.IssueId = x.Des
                                     WHERE x.FuenteId = i.FuenteId AND x.Anc = i.IssueId AND x.D > 0 AND d.EstimacionOriginalSeg > 0)
                THEN CAST(i.EstimacionOriginalSeg AS bigint) END AS EstEf
    INTO #e
    FROM #i i;

    SELECT p.FuenteId, p.Anc AS IssueId,
           SUM(h.SegReg) AS SegReg, SUM(h.SegAut) AS SegAut, SUM(h.SegCop) AS SegCop, SUM(e.EstEf) AS Est, MAX(h.Ultimo) AS Ultimo,
           COUNT(*) AS Elementos, SUM(CASE WHEN d.Abierto = 1 THEN 1 ELSE 0 END) AS Abiertos
    INTO #t
    FROM #par p
    JOIN #i d ON d.FuenteId = p.FuenteId AND d.IssueId = p.Des
    LEFT JOIN #h h ON h.FuenteId = p.FuenteId AND h.IssueId = p.Des
    LEFT JOIN #e e ON e.FuenteId = p.FuenteId AND e.IssueId = p.Des
    GROUP BY p.FuenteId, p.Anc;

    -- Proyectos: suma de sus raíces (épicas y lo que va en "(Sin épica)").
    SELECT n.ProyectoClave, MAX(i.ProyectoNombre) AS ProyectoNombre,
           SUM(t.SegReg) AS SegReg, SUM(t.SegAut) AS SegAut, SUM(t.SegCop) AS SegCop, SUM(t.Est) AS Est, MAX(t.Ultimo) AS Ultimo,
           SUM(t.Elementos) AS Elementos, SUM(t.Abiertos) AS Abiertos
    INTO #p
    FROM #n n
    JOIN #i i ON i.FuenteId = n.FuenteId AND i.IssueId = n.IssueId
    JOIN #t t ON t.FuenteId = n.FuenteId AND t.IssueId = n.IssueId
    WHERE n.Nivel = 2 OR n.PadreNodo LIKE N'S|%'
    GROUP BY n.ProyectoClave;

    SELECT x.Nodo, x.PadreNodo, x.Nivel,
           CASE x.Nivel WHEN 0 THEN N'Total' WHEN 1 THEN N'Proyecto' WHEN 2 THEN N'Épica' WHEN 3 THEN N'Tarea' ELSE N'Subtarea' END AS NivelNombre,
           x.Clave, x.Elemento, x.Tipo, x.Estado, x.Responsable,
           CAST(x.SegReg / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(x.SegAut / 3600.0 AS decimal(12,2)) AS HorasAutomaticas,
           CAST(x.SegCop / 3600.0 AS decimal(12,2)) AS HorasCopiadas,
           CAST(x.SegPropio / 3600.0 AS decimal(12,2)) AS HorasPropias,
           CAST(x.Est / 3600.0 AS decimal(12,2)) AS HorasEstimadas,
           CAST(CASE WHEN x.Est > 0 THEN 100.0 * ISNULL(x.SegReg, 0) / x.Est END AS decimal(9,1)) AS PorcentajeConsumido,
           x.Elementos, x.Abiertos, x.Ultimo AS UltimoRegistro
    FROM (
        -- Total
        SELECT N'#total' AS Nodo, CAST(NULL AS nvarchar(60)) AS PadreNodo, 0 AS Nivel, CAST(NULL AS varchar(50)) AS Clave,
               CAST(CONCAT(CASE WHEN @Proyecto IS NULL THEN N'Total' ELSE N'Total del proyecto' END,
                    CASE WHEN @Desde IS NULL AND @Hasta IS NULL THEN N' (todo el historial)'
                         ELSE CONCAT(N' del ', ISNULL(CONVERT(nvarchar(10), @Desde, 103), N'inicio'), N' al ', CONVERT(nvarchar(10), ISNULL(@Hasta, CAST(SYSDATETIME() AS date)), 103)) END)
                    AS nvarchar(400)) AS Elemento,
               CAST(NULL AS nvarchar(255)) AS Tipo, CAST(NULL AS nvarchar(100)) AS Estado, CAST(NULL AS nvarchar(255)) AS Responsable,
               SUM(SegReg) AS SegReg, SUM(SegAut) AS SegAut, SUM(SegCop) AS SegCop, CAST(NULL AS bigint) AS SegPropio,
               SUM(Est) AS Est, MAX(Ultimo) AS Ultimo, SUM(Elementos) AS Elementos, SUM(Abiertos) AS Abiertos, CAST('' AS varchar(400)) AS Ruta
        FROM #p
        UNION ALL
        -- Proyectos
        SELECT N'P|' + p.ProyectoClave, N'#total', 1, NULL, CAST(p.ProyectoClave + N' · ' + p.ProyectoNombre AS nvarchar(400)), N'Proyecto', NULL, NULL,
               p.SegReg, p.SegAut, p.SegCop, NULL, p.Est, p.Ultimo, p.Elementos, p.Abiertos, CAST(LEFT(p.ProyectoClave + SPACE(20), 20) AS varchar(400))
        FROM #p p
        UNION ALL
        -- Tareas (y subtareas sueltas) sin épica, por proyecto
        SELECT N'S|' + n.ProyectoClave, N'P|' + n.ProyectoClave, 2, NULL, N'(Sin épica)', N'Agrupador', NULL, NULL,
               SUM(t.SegReg), SUM(t.SegAut), SUM(t.SegCop), NULL, SUM(t.Est), MAX(t.Ultimo), SUM(t.Elementos), SUM(t.Abiertos),
               CAST(LEFT(n.ProyectoClave + SPACE(20), 20) + '/2' AS varchar(400))
        FROM #n n JOIN #t t ON t.FuenteId = n.FuenteId AND t.IssueId = n.IssueId
        WHERE n.PadreNodo LIKE N'S|%'
        GROUP BY n.ProyectoClave
        UNION ALL
        SELECT CAST(n.Clave AS nvarchar(60)), n.PadreNodo, n.Nivel, n.Clave, i.Resumen, i.TipoIssue, i.Estado, i.Responsable,
               t.SegReg, t.SegAut, t.SegCop, h.SegReg, t.Est, t.Ultimo, t.Elementos, t.Abiertos, n.Ruta
        FROM #n n
        JOIN #i i ON i.FuenteId = n.FuenteId AND i.IssueId = n.IssueId
        JOIN #t t ON t.FuenteId = n.FuenteId AND t.IssueId = n.IssueId
        LEFT JOIN #h h ON h.FuenteId = n.FuenteId AND h.IssueId = n.IssueId
    ) x
    WHERE @SoloConHoras = 0 OR x.Nivel = 0 OR ISNULL(x.SegReg, 0) + ISNULL(x.SegAut, 0) + ISNULL(x.SegCop, 0) > 0
    ORDER BY x.Ruta;
END;
GO
