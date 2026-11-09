/* Horas registradas en un issue MÁS las de todos sus descendientes, separadas por origen (como rpt.vWorklog):
   manual = las registró una persona; automático = una app (Automation for Jira).
   Una tarea suma sus subtareas; una épica suma sus tareas y las subtareas de éstas (en Scrum las personas registran
   en las subtareas). Profundidad máxima 5 niveles. NULL = no tiene worklogs de ese origen. */
CREATE OR ALTER FUNCTION rpt.fn_HorasIssue (@FuenteId int, @IssueId varchar(30), @Clave varchar(50))
RETURNS TABLE
AS
RETURN
    WITH arbol AS (
        SELECT CAST(@IssueId AS varchar(30)) AS IssueId, CAST(@Clave AS varchar(50)) AS Clave, 0 AS Nivel
        UNION ALL
        SELECT h.IssueId, h.Clave, a.Nivel + 1
        FROM arbol a JOIN ops.Issue h ON h.FuenteId = @FuenteId AND h.PadreClave = a.Clave
        WHERE h.Eliminado = 0 AND a.Nivel < 5
    )
    SELECT CAST(SUM(CASE WHEN ISNULL(u.TipoCuenta, '') <> 'app' THEN w.Segundos END) / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(SUM(CASE WHEN u.TipoCuenta = 'app' THEN w.Segundos END) / 3600.0 AS decimal(12,2)) AS HorasAutomaticas,
           MAX(w.Inicio) AS UltimoRegistro,
           -- Estimación original de todo el árbol (como aggregatetimeoriginalestimate de Jira).
           CAST((SELECT SUM(x.EstimacionOriginalSeg) FROM arbol b JOIN ops.Issue x ON x.FuenteId = @FuenteId AND x.IssueId = b.IssueId) / 3600.0 AS decimal(12,2)) AS HorasEstimadas
    FROM arbol a
    JOIN ops.Worklog w ON w.FuenteId = @FuenteId AND w.IssueId = a.IssueId AND w.Eliminado = 0
    LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId;
GO
