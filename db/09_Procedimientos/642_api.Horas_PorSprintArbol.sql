/* Horas por sprint en jerarquía, con subtotales: Total → sprint → persona → tarea / historia → subtarea.
   Mismas reglas que api.Horas_PorSprint: cuenta los worklogs dentro de la ventana del sprint (de su inicio a su cierre y
   nunca después del inicio del siguiente sprint del mismo tablero) en los issues del sprint y en sus subtareas; las
   automáticas se atribuyen al responsable del issue ese día y las copias automáticas no se suman.
   Cada worklog se suma en su issue y en sus antecesores (subtarea → su tarea → persona → sprint → total), así cada fila
   es el subtotal de lo que tiene debajo. Una fila por nodo: Nodo / PadreNodo / Nivel / NivelNombre arman el árbol. */
CREATE OR ALTER PROCEDURE api.Horas_PorSprintArbol
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL,       -- future | active | closed
    @Sprint   nvarchar(255) = NULL,     -- parte del nombre
    @Persona  nvarchar(200) = NULL      -- parte del nombre (vacío = todas)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.FuenteId, s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado,
           COALESCE(s.Completado, CASE WHEN s.Estado = 'active' AND SYSDATETIMEOFFSET() > s.Fin THEN SYSDATETIMEOFFSET() END, s.Fin) AS FinEfectivo,
           (SELECT MIN(n.Inicio) FROM ops.Sprint n
            WHERE n.FuenteId = s.FuenteId AND n.TableroId = s.TableroId AND n.SprintId <> s.SprintId AND n.Inicio > s.Inicio) AS InicioSiguiente
    INTO #s FROM ops.Sprint s
    WHERE (@Estado IS NULL OR s.Estado = @Estado) AND (@Sprint IS NULL OR CHARINDEX(@Sprint, s.Nombre) > 0);
    ALTER TABLE #s ADD FinVentana datetimeoffset(3) NULL;
    UPDATE #s SET FinVentana = CASE WHEN InicioSiguiente IS NOT NULL AND InicioSiguiente < FinEfectivo THEN InicioSiguiente ELSE FinEfectivo END;

    SELECT x.FuenteId, x.SprintId, i.IssueId, i.PadreId, i.EsSubtarea, i.ProyectoClave
    INTO #iss
    FROM ops.IssueSprint x
    JOIN #s s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
    JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
    WHERE @Proyecto IS NULL OR i.ProyectoClave = @Proyecto;

    -- Issues cuyo tiempo cuenta y la tarea / historia del sprint bajo la que van (una subtarea, bajo su tarea).
    SELECT FuenteId, SprintId, IssueId, MIN(TareaId) AS TareaId INTO #m FROM (
        SELECT i.FuenteId, i.SprintId, i.IssueId,
               CASE WHEN i.EsSubtarea = 1 AND EXISTS (SELECT 1 FROM #iss p WHERE p.FuenteId = i.FuenteId AND p.SprintId = i.SprintId AND p.IssueId = i.PadreId)
                    THEN i.PadreId ELSE i.IssueId END AS TareaId
        FROM #iss i
        UNION ALL
        SELECT st.FuenteId, i.SprintId, st.IssueId, i.IssueId
        FROM #iss i JOIN ops.Issue st ON st.FuenteId = i.FuenteId AND st.PadreId = i.IssueId AND st.EsSubtarea = 1 AND st.Eliminado = 0
        WHERE i.EsSubtarea = 0
    ) u
    GROUP BY FuenteId, SprintId, IssueId;
    CREATE CLUSTERED INDEX ix ON #m (FuenteId, IssueId, SprintId);

    SELECT m.FuenteId, m.SprintId, m.IssueId, m.TareaId, w.WorklogId INTO #w
    FROM #m m
    JOIN #s s ON s.FuenteId = m.FuenteId AND s.SprintId = m.SprintId
    JOIN ops.Worklog w WITH (FORCESEEK(IX_ops_Worklog_IssueDet(FuenteId, IssueId))) ON w.FuenteId = m.FuenteId AND w.IssueId = m.IssueId
    WHERE w.Eliminado = 0 AND ISNULL(w.EsCopia, 0) = 0 AND w.Inicio >= s.Inicio AND w.Inicio < s.FinVentana;   -- sin copias automáticas
    CREATE CLUSTERED INDEX ix ON #w (FuenteId, WorklogId);

    -- Horas por sprint, persona e issue.
    SELECT x.FuenteId, x.SprintId, w.AtribuidoA AS Persona, x.TareaId, x.IssueId,
           SUM(CASE WHEN w.Origen = 'manual' THEN CAST(w.Segundos AS bigint) ELSE 0 END) AS SegReg,
           SUM(CASE WHEN w.Origen = 'automatico' THEN CAST(w.Segundos AS bigint) ELSE 0 END) AS SegAut
    INTO #h
    FROM #w x
    JOIN rpt.vWorklog w ON w.FuenteId = x.FuenteId AND w.WorklogId = x.WorklogId
    WHERE @Persona IS NULL OR w.AtribuidoA LIKE N'%' + @Persona + N'%'
    GROUP BY x.FuenteId, x.SprintId, w.AtribuidoA, x.TareaId, x.IssueId
    OPTION (FORCE ORDER);   -- ver api.Issue_Detalle

    -- Orden: sprints del más reciente al más antiguo; personas de más a menos horas; tareas por número.
    SELECT s.FuenteId, s.SprintId, s.Nombre, s.Estado, s.Inicio, s.FinVentana,
           (SELECT MIN(i.ProyectoClave) FROM #iss i WHERE i.FuenteId = s.FuenteId AND i.SprintId = s.SprintId) AS Proyecto,
           RIGHT('00000' + CAST(ROW_NUMBER() OVER (ORDER BY s.Inicio DESC, s.SprintId) AS varchar(6)), 6) AS Orden
    INTO #so FROM #s s
    WHERE EXISTS (SELECT 1 FROM #h h WHERE h.FuenteId = s.FuenteId AND h.SprintId = s.SprintId);

    SELECT FuenteId, SprintId, Persona,
           RIGHT('00000' + CAST(ROW_NUMBER() OVER (PARTITION BY FuenteId, SprintId ORDER BY SUM(SegReg) DESC, SUM(SegAut) DESC, Persona) AS varchar(6)), 6) AS Orden
    INTO #po FROM #h GROUP BY FuenteId, SprintId, Persona;

    SELECT x.Nodo, x.PadreNodo, x.Nivel,
           CASE x.Nivel WHEN 0 THEN N'Total' WHEN 1 THEN N'Sprint' WHEN 2 THEN N'Persona' WHEN 3 THEN N'Tarea' ELSE N'Subtarea' END AS NivelNombre,
           x.Clave, x.Elemento, x.Tipo, x.Estado,
           CAST(x.SegReg / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(x.SegAut / 3600.0 AS decimal(12,2)) AS HorasAutomaticas,
           CAST((x.SegReg + x.SegAut) / 3600.0 AS decimal(12,2)) AS HorasTotales,
           CAST(x.SegPropios / 3600.0 AS decimal(12,2)) AS HorasPropias,
           x.IssuesConHoras
    FROM (
        SELECT CAST(N'#total' AS nvarchar(300)) AS Nodo, CAST(NULL AS nvarchar(300)) AS PadreNodo, 0 AS Nivel, CAST(NULL AS varchar(50)) AS Clave,
               CAST(N'Total' AS nvarchar(400)) AS Elemento, CAST(NULL AS nvarchar(255)) AS Tipo, CAST(NULL AS nvarchar(255)) AS Estado,
               SUM(SegReg) AS SegReg, SUM(SegAut) AS SegAut, CAST(NULL AS bigint) AS SegPropios,
               COUNT(DISTINCT CONCAT(FuenteId, N'|', IssueId)) AS IssuesConHoras, CAST('' AS varchar(200)) AS Ruta
        FROM #h
        HAVING COUNT(*) > 0
        UNION ALL
        -- Sprints
        SELECT N's' + so.Orden, N'#total', 1, NULL,
               CAST(ISNULL(so.Proyecto + N' · ', N'') + so.Nombre + N' (' + CONVERT(nvarchar(10), CAST(so.Inicio AS date), 103) + N' – '
                    + CONVERT(nvarchar(10), CAST(so.FinVentana AS date), 103) + N')' AS nvarchar(400)),
               N'Sprint', CASE so.Estado WHEN 'active' THEN N'Activo' WHEN 'closed' THEN N'Cerrado' WHEN 'future' THEN N'Futuro' ELSE so.Estado END,
               SUM(h.SegReg), SUM(h.SegAut), NULL, COUNT(DISTINCT h.IssueId), CAST(so.Orden AS varchar(200))
        FROM #so so JOIN #h h ON h.FuenteId = so.FuenteId AND h.SprintId = so.SprintId
        GROUP BY so.Orden, so.Proyecto, so.Nombre, so.Inicio, so.FinVentana, so.Estado
        UNION ALL
        -- Personas
        SELECT N's' + so.Orden + N'|p' + po.Orden, N's' + so.Orden, 2, NULL, CAST(po.Persona AS nvarchar(400)), N'Persona', NULL,
               SUM(h.SegReg), SUM(h.SegAut), NULL, COUNT(DISTINCT h.IssueId), CAST(so.Orden + '/' + po.Orden AS varchar(200))
        FROM #po po
        JOIN #so so ON so.FuenteId = po.FuenteId AND so.SprintId = po.SprintId
        JOIN #h h ON h.FuenteId = po.FuenteId AND h.SprintId = po.SprintId AND h.Persona = po.Persona
        GROUP BY so.Orden, po.Orden, po.Persona
        UNION ALL
        -- Tareas / historias del sprint
        SELECT N's' + so.Orden + N'|p' + po.Orden + N'|' + t.Clave, N's' + so.Orden + N'|p' + po.Orden, 3, t.Clave, t.Resumen, t.TipoIssue, t.Estado,
               SUM(h.SegReg), SUM(h.SegAut), SUM(CASE WHEN h.IssueId = h.TareaId THEN h.SegReg + h.SegAut END), COUNT(DISTINCT h.IssueId),
               CAST(so.Orden + '/' + po.Orden + '/' + RIGHT(REPLICATE('0', 9) + CAST(ISNULL(TRY_CAST(SUBSTRING(t.Clave, CHARINDEX('-', t.Clave) + 1, 20) AS int), 0) AS varchar(10)), 9) AS varchar(200))
        FROM #h h
        JOIN #so so ON so.FuenteId = h.FuenteId AND so.SprintId = h.SprintId
        JOIN #po po ON po.FuenteId = h.FuenteId AND po.SprintId = h.SprintId AND po.Persona = h.Persona
        JOIN rpt.vIssue t ON t.FuenteId = h.FuenteId AND t.IssueId = h.TareaId
        GROUP BY so.Orden, po.Orden, t.Clave, t.Resumen, t.TipoIssue, t.Estado
        UNION ALL
        -- Subtareas
        SELECT N's' + so.Orden + N'|p' + po.Orden + N'|' + t.Clave + N'|' + st.Clave, N's' + so.Orden + N'|p' + po.Orden + N'|' + t.Clave, 4,
               st.Clave, st.Resumen, st.TipoIssue, st.Estado, h.SegReg, h.SegAut, h.SegReg + h.SegAut, 1,
               CAST(so.Orden + '/' + po.Orden + '/' + RIGHT(REPLICATE('0', 9) + CAST(ISNULL(TRY_CAST(SUBSTRING(t.Clave, CHARINDEX('-', t.Clave) + 1, 20) AS int), 0) AS varchar(10)), 9)
                    + '/' + RIGHT(REPLICATE('0', 9) + CAST(ISNULL(TRY_CAST(SUBSTRING(st.Clave, CHARINDEX('-', st.Clave) + 1, 20) AS int), 0) AS varchar(10)), 9) AS varchar(200))
        FROM #h h
        JOIN #so so ON so.FuenteId = h.FuenteId AND so.SprintId = h.SprintId
        JOIN #po po ON po.FuenteId = h.FuenteId AND po.SprintId = h.SprintId AND po.Persona = h.Persona
        JOIN rpt.vIssue t ON t.FuenteId = h.FuenteId AND t.IssueId = h.TareaId
        JOIN rpt.vIssue st ON st.FuenteId = h.FuenteId AND st.IssueId = h.IssueId
        WHERE h.IssueId <> h.TareaId
    ) x
    ORDER BY x.Ruta;
END;
GO
