/* Horas registradas en un issue MÁS las de sus subtareas, separadas por origen (como rpt.vWorklog):
   manual = las registró una persona; automático = una app (Automation for Jira).
   En Scrum las personas registran el tiempo en las subtareas: así una historia muestra todo su esfuerzo.
   NULL = no tiene worklogs de ese origen. */
CREATE OR ALTER FUNCTION rpt.fn_HorasIssue (@FuenteId int, @IssueId varchar(30), @Clave varchar(50))
RETURNS TABLE
AS
RETURN
    SELECT CAST(SUM(CASE WHEN ISNULL(u.TipoCuenta, '') <> 'app' THEN w.Segundos END) / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(SUM(CASE WHEN u.TipoCuenta = 'app' THEN w.Segundos END) / 3600.0 AS decimal(12,2)) AS HorasAutomaticas
    FROM ops.Worklog w
    LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
    WHERE w.FuenteId = @FuenteId AND w.Eliminado = 0
      AND (w.IssueId = @IssueId
           OR w.IssueId IN (SELECT s.IssueId FROM ops.Issue s
                            WHERE s.FuenteId = @FuenteId AND s.PadreClave = @Clave AND s.EsSubtarea = 1 AND s.Eliminado = 0));
GO
