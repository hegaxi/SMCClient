/* Cambios de estado con el tiempo que el issue pasó en cada estado (base para lead/cycle time). */
CREATE OR ALTER VIEW rpt.vTransicionEstado
AS
SELECT
    c.IssueSk, i.Clave, i.ProyectoClave, c.Fecha, c.AutorId,
    c.Desde AS EstadoDesdeId, c.DesdeTexto AS EstadoDesde,
    c.Hacia AS EstadoHaciaId, c.HaciaTexto AS EstadoHacia,
    LEAD(c.Fecha) OVER (PARTITION BY c.IssueSk ORDER BY c.Fecha, c.HistoriaId) AS SiguienteCambio,
    DATEDIFF(MINUTE, c.Fecha, COALESCE(LEAD(c.Fecha) OVER (PARTITION BY c.IssueSk ORDER BY c.Fecha, c.HistoriaId), SYSDATETIMEOFFSET())) AS MinutosEnEstado
FROM ops.IssueCambio c
JOIN rpt.vIssue i ON i.IssueSk = c.IssueSk
WHERE c.CampoId = 'status';
GO
