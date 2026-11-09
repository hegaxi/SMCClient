/* Tiempo reportado en Scrum: horas por sprint y persona.
   Cuenta los worklogs registrados dentro de las fechas del sprint (ver api.Sprint_Avance) en los issues del sprint y
   en sus subtareas (donde las personas suelen registrar el tiempo). Las horas automáticas (Automation for Jira) se
   atribuyen al responsable del issue ese día, igual que en api.Horas_PorPersona (rpt.vWorklog). */
CREATE OR ALTER PROCEDURE api.Horas_PorSprint
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL,       -- future | active | closed
    @Sprint   nvarchar(255) = NULL      -- parte del nombre
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.FuenteId, s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin,
           COALESCE(s.Completado, CASE WHEN s.Estado = 'active' AND SYSDATETIMEOFFSET() > s.Fin THEN SYSDATETIMEOFFSET() END, s.Fin) AS FinEfectivo
    INTO #s FROM ops.Sprint s
    WHERE (@Estado IS NULL OR s.Estado = @Estado) AND (@Sprint IS NULL OR CHARINDEX(@Sprint, s.Nombre) > 0);

    SELECT x.FuenteId, x.SprintId, i.IssueSk, i.IssueId
    INTO #iss
    FROM ops.IssueSprint x
    JOIN #s s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
    JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
    WHERE @Proyecto IS NULL OR i.ProyectoClave = @Proyecto;

    SELECT DISTINCT FuenteId, SprintId, IssueId INTO #m FROM (
        SELECT FuenteId, SprintId, IssueId FROM #iss
        UNION ALL
        SELECT st.FuenteId, i.SprintId, st.IssueId
        FROM #iss i JOIN ops.Issue st ON st.FuenteId = i.FuenteId AND st.PadreId = i.IssueId AND st.EsSubtarea = 1 AND st.Eliminado = 0
    ) u;
    CREATE CLUSTERED INDEX ix ON #m (FuenteId, IssueId, SprintId);

    -- Primero los ids de los worklogs, buscando por (FuenteId, IssueId) en su índice (forzado: con estadísticas recién
    -- cargadas el optimizador llegó a recorrer todos los worklogs de la fuente por cada issue); luego la vista por llave.
    SELECT m.FuenteId, m.SprintId, w.WorklogId INTO #w
    FROM #m m
    JOIN #s s ON s.FuenteId = m.FuenteId AND s.SprintId = m.SprintId
    JOIN ops.Worklog w WITH (FORCESEEK(IX_ops_Worklog_IssueDet(FuenteId, IssueId))) ON w.FuenteId = m.FuenteId AND w.IssueId = m.IssueId
    WHERE w.Eliminado = 0 AND w.Inicio >= s.Inicio AND w.Inicio < s.FinEfectivo;
    CREATE CLUSTERED INDEX ix ON #w (FuenteId, WorklogId, SprintId);

    SELECT s.Nombre AS Sprint, s.Estado, s.Inicio, s.Fin, w.AtribuidoA AS Persona,
           COUNT(DISTINCT w.IssueSk) AS Issues,
           CAST(SUM(CASE WHEN w.Origen = 'manual' THEN w.Horas ELSE 0 END) AS decimal(12,2)) AS HorasRegistradas,
           CAST(SUM(CASE WHEN w.Origen = 'automatico' THEN w.Horas ELSE 0 END) AS decimal(12,2)) AS HorasAutomaticas,
           CAST(SUM(w.Horas) AS decimal(12,2)) AS HorasTotales
    FROM #w x
    JOIN #s s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
    JOIN rpt.vWorklog w ON w.FuenteId = x.FuenteId AND w.WorklogId = x.WorklogId
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, w.AtribuidoA
    ORDER BY s.Inicio DESC, HorasRegistradas DESC, HorasTotales DESC
    OPTION (FORCE ORDER);   -- ver api.Issue_Detalle
END;
GO
