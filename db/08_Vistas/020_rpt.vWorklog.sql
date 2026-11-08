CREATE OR ALTER VIEW rpt.vWorklog
AS
SELECT
    w.FuenteId, w.WorklogId, i.IssueSk, i.Clave, i.ProyectoClave, i.TipoProyecto,
    w.AutorId, u.Nombre AS Autor, u.TipoCuenta AS TipoCuentaAutor,
    w.Inicio, CAST(w.Inicio AS date) AS Fecha, w.Segundos, CAST(w.Segundos / 3600.0 AS decimal(12,2)) AS Horas
FROM ops.Worklog w
JOIN rpt.vIssue i ON i.FuenteId = w.FuenteId AND i.IssueId = w.IssueId
LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
WHERE w.Eliminado = 0;
GO
