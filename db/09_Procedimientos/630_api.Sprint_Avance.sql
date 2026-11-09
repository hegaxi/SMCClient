/* Avance por sprint: issues (sin contar subtareas), terminados, story points y horas.
   Horas = worklogs registrados DENTRO de las fechas del sprint (de su inicio a su cierre; si sigue activo después de
   su fecha de fin, hasta hoy) en los issues del sprint y en sus subtareas, cada worklog una sola vez. Así un issue que
   pasa de un sprint a otro no repite horas, y se separan las que registraron las personas de las automáticas. */
CREATE OR ALTER PROCEDURE api.Sprint_Avance
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL    -- future | active | closed
AS
BEGIN
    SET NOCOUNT ON;
    WITH s AS (
        SELECT s.FuenteId, s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado,
               COALESCE(s.Completado, CASE WHEN s.Estado = 'active' AND SYSDATETIMEOFFSET() > s.Fin THEN SYSDATETIMEOFFSET() END, s.Fin) AS FinEfectivo
        FROM ops.Sprint s WHERE @Estado IS NULL OR s.Estado = @Estado
    ),
    iss AS (
        SELECT x.FuenteId, x.SprintId, i.IssueId, i.Clave, i.CategoriaEstado, i.StoryPoints, i.EsSubtarea
        FROM ops.IssueSprint x JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
        WHERE @Proyecto IS NULL OR i.ProyectoClave = @Proyecto
    ),
    horas AS (
        SELECT s.FuenteId, s.SprintId,
               SUM(CASE WHEN ISNULL(u.TipoCuenta, '') <> 'app' THEN w.Segundos END) / 3600.0 AS Registradas,
               SUM(CASE WHEN u.TipoCuenta = 'app' THEN w.Segundos END) / 3600.0 AS Automaticas
        FROM s
        JOIN ops.Worklog w ON w.FuenteId = s.FuenteId AND w.Eliminado = 0 AND w.Inicio >= s.Inicio AND w.Inicio < s.FinEfectivo
        LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
        WHERE EXISTS (SELECT 1 FROM iss WHERE iss.FuenteId = s.FuenteId AND iss.SprintId = s.SprintId AND iss.IssueId = w.IssueId)
           OR EXISTS (SELECT 1 FROM ops.Issue st JOIN iss ON iss.FuenteId = st.FuenteId AND iss.SprintId = s.SprintId AND iss.Clave = st.PadreClave
                      WHERE st.FuenteId = w.FuenteId AND st.IssueId = w.IssueId AND st.EsSubtarea = 1 AND st.Eliminado = 0)
        GROUP BY s.FuenteId, s.SprintId
    )
    SELECT s.SprintId, s.Nombre AS Sprint, s.Estado, s.Inicio, s.Fin, s.Completado,
           SUM(CASE WHEN iss.EsSubtarea = 0 THEN 1 ELSE 0 END) AS Issues,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.CategoriaEstado = 'done' THEN 1 ELSE 0 END) AS Terminados,
           SUM(iss.StoryPoints) AS StoryPoints,
           SUM(CASE WHEN iss.CategoriaEstado = 'done' THEN iss.StoryPoints END) AS StoryPointsTerminados,
           CAST(MAX(h.Registradas) AS decimal(12,2)) AS HorasRegistradas,
           CAST(MAX(h.Automaticas) AS decimal(12,2)) AS HorasAutomaticas
    FROM s
    JOIN iss ON iss.FuenteId = s.FuenteId AND iss.SprintId = s.SprintId
    LEFT JOIN horas h ON h.FuenteId = s.FuenteId AND h.SprintId = s.SprintId
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado
    ORDER BY s.Inicio DESC;
END;
GO
