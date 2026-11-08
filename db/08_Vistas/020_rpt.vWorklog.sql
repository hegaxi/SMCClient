/* Worklogs con su ORIGEN y la persona a la que se ATRIBUYEN.

   Origen: 'manual' si lo registró una persona; 'automatico' si lo registró una app (accountType = app,
   p. ej. Automation for Jira, que en smco registra 1 día por cada día hábil que el issue sigue abierto).

   Atribución (se calcula al consultar, así se corrige sola si el historial llega después):
     manual      -> el autor.
     automatico  -> el responsable del issue el día del worklog, según el historial de cambios del
                    campo assignee: el último cambio hasta esa fecha; si no hubo cambios antes, el
                    responsable "desde" del primer cambio posterior; si nunca cambió, el responsable actual.
                    NULL = el issue no tenía responsable ese día.
   El autor original de Jira se conserva siempre en AutorId / Autor. */
CREATE OR ALTER VIEW rpt.vWorklog
AS
SELECT
    w.FuenteId, w.WorklogId, i.IssueSk, i.Clave, i.ProyectoClave, i.TipoProyecto,
    w.AutorId, u.Nombre AS Autor, u.TipoCuenta AS TipoCuentaAutor,
    o.Origen,
    a.AtribuidoAId,
    COALESCE(ua.Nombre, CASE WHEN a.AtribuidoAId IS NULL THEN N'(Sin responsable)' ELSE a.AtribuidoAId END) AS AtribuidoA,
    a.Metodo AS MetodoAtribucion,
    w.Inicio, CAST(w.Inicio AS date) AS Fecha, w.Segundos, CAST(w.Segundos / 3600.0 AS decimal(12,2)) AS Horas
FROM ops.Worklog w
JOIN rpt.vIssue i ON i.FuenteId = w.FuenteId AND i.IssueId = w.IssueId
LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
CROSS APPLY (SELECT CASE WHEN u.TipoCuenta = 'app' THEN 'automatico' ELSE 'manual' END AS Origen) o
OUTER APPLY (
    SELECT TOP (1) c.Hacia FROM ops.IssueCambio c
    WHERE c.IssueSk = i.IssueSk AND c.CampoId = 'assignee' AND c.Fecha <= w.Inicio
    ORDER BY c.Fecha DESC, c.HistoriaId DESC, c.Orden DESC
) antes
OUTER APPLY (
    SELECT TOP (1) c.Desde FROM ops.IssueCambio c
    WHERE c.IssueSk = i.IssueSk AND c.CampoId = 'assignee' AND c.Fecha > w.Inicio
    ORDER BY c.Fecha, c.HistoriaId, c.Orden
) despues
OUTER APPLY (
    SELECT TOP (1) 1 AS Hay FROM ops.IssueCambio c WHERE c.IssueSk = i.IssueSk AND c.CampoId = 'assignee'
) historial
CROSS APPLY (
    SELECT
        CASE WHEN o.Origen = 'manual' THEN w.AutorId
             WHEN historial.Hay IS NULL THEN i.ResponsableId
             WHEN EXISTS (SELECT 1 FROM ops.IssueCambio c WHERE c.IssueSk = i.IssueSk AND c.CampoId = 'assignee' AND c.Fecha <= w.Inicio) THEN antes.Hacia
             ELSE despues.Desde END AS AtribuidoAId,
        CASE WHEN o.Origen = 'manual' THEN 'autor'
             WHEN historial.Hay IS NULL THEN 'responsable_actual'
             ELSE 'historial' END AS Metodo
) a
LEFT JOIN ops.Usuario ua ON ua.FuenteId = w.FuenteId AND ua.AccountId = a.AtribuidoAId
WHERE w.Eliminado = 0;
GO
