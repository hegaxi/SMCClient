/* Avance por sprint: issues (sin contar subtareas), terminados, story points y horas.
   Horas = worklogs registrados DENTRO de las fechas del sprint (de su inicio a su cierre; si sigue activo después de
   su fecha de fin, hasta hoy) en los issues del sprint y en sus subtareas, cada worklog una sola vez. Así un issue que
   pasa de un sprint a otro no repite horas, y se separan las que registraron las personas de las automáticas.
   Se arma con tablas temporales indexadas (la versión con CTE tardaba minutos con 500 000 worklogs). */
CREATE OR ALTER PROCEDURE api.Sprint_Avance
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL    -- future | active | closed
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.FuenteId, s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado,
           COALESCE(s.Completado, CASE WHEN s.Estado = 'active' AND SYSDATETIMEOFFSET() > s.Fin THEN SYSDATETIMEOFFSET() END, s.Fin) AS FinEfectivo
    INTO #s FROM ops.Sprint s WHERE @Estado IS NULL OR s.Estado = @Estado;

    SELECT x.FuenteId, x.SprintId, i.IssueId, i.CategoriaEstado, i.StoryPoints, i.EsSubtarea
    INTO #iss
    FROM ops.IssueSprint x
    JOIN #s s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
    JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
    WHERE @Proyecto IS NULL OR i.ProyectoClave = @Proyecto;

    -- Issues cuyos worklogs cuentan para el sprint: los del sprint y sus subtareas.
    SELECT DISTINCT FuenteId, SprintId, IssueId INTO #m FROM (
        SELECT FuenteId, SprintId, IssueId FROM #iss
        UNION ALL
        SELECT st.FuenteId, i.SprintId, st.IssueId
        FROM #iss i JOIN ops.Issue st ON st.FuenteId = i.FuenteId AND st.PadreId = i.IssueId AND st.EsSubtarea = 1 AND st.Eliminado = 0
    ) u;
    CREATE CLUSTERED INDEX ix ON #m (FuenteId, IssueId, SprintId);

    SELECT m.FuenteId, m.SprintId,
           SUM(CASE WHEN COALESCE(w.EsAutomatico, CASE WHEN u.TipoCuenta = 'app' THEN 1 ELSE 0 END) = 0 THEN CAST(w.Segundos AS bigint) END) / 3600.0 AS Registradas,
           SUM(CASE WHEN COALESCE(w.EsAutomatico, CASE WHEN u.TipoCuenta = 'app' THEN 1 ELSE 0 END) = 1 THEN CAST(w.Segundos AS bigint) END) / 3600.0 AS Automaticas
    INTO #horas
    FROM #m m
    JOIN #s s ON s.FuenteId = m.FuenteId AND s.SprintId = m.SprintId
    JOIN ops.Worklog w ON w.FuenteId = m.FuenteId AND w.IssueId = m.IssueId AND w.Eliminado = 0 AND w.Inicio >= s.Inicio AND w.Inicio < s.FinEfectivo
    LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
    GROUP BY m.FuenteId, m.SprintId;

    SELECT s.SprintId, s.Nombre AS Sprint, s.Estado, s.Inicio, s.Fin, s.Completado,
           SUM(CASE WHEN iss.EsSubtarea = 0 THEN 1 ELSE 0 END) AS Issues,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.CategoriaEstado = 'done' THEN 1 ELSE 0 END) AS Terminados,
           SUM(iss.StoryPoints) AS StoryPoints,
           SUM(CASE WHEN iss.CategoriaEstado = 'done' THEN iss.StoryPoints END) AS StoryPointsTerminados,
           CAST(MAX(h.Registradas) AS decimal(12,2)) AS HorasRegistradas,
           CAST(MAX(h.Automaticas) AS decimal(12,2)) AS HorasAutomaticas
    FROM #s s
    JOIN #iss iss ON iss.FuenteId = s.FuenteId AND iss.SprintId = s.SprintId
    LEFT JOIN #horas h ON h.FuenteId = s.FuenteId AND h.SprintId = s.SprintId
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado
    ORDER BY s.Inicio DESC;
END;
GO
