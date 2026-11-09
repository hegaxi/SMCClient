/* Worklogs con su ORIGEN y la persona a la que se ATRIBUYEN.
   La regla está en sync.Worklog_Atribuir, que guarda el resultado al integrar (antes se calculaba aquí en cada consulta
   y tardaba ~25 s para un año de worklogs en la prueba de carga):
     manual      -> el autor.
     automatico  -> el responsable del issue el día del worklog, según el historial del campo assignee.
   Si un worklog aún no tiene atribución guardada (recién llegado), se usa la regla simple: manual -> autor,
   automático -> responsable actual. El autor original de Jira se conserva siempre en AutorId / Autor. */
CREATE OR ALTER VIEW rpt.vWorklog
AS
SELECT
    w.FuenteId, w.WorklogId, w.IssueId, i.IssueSk, i.Clave, i.ProyectoClave, i.TipoProyecto,
    w.AutorId, u.Nombre AS Autor, u.TipoCuenta AS TipoCuentaAutor,
    CASE WHEN COALESCE(w.EsAutomatico, CASE WHEN u.TipoCuenta = 'app' THEN 1 ELSE 0 END) = 1 THEN 'automatico' ELSE 'manual' END AS Origen,
    a.AtribuidoAId,
    COALESCE(ua.Nombre, CASE WHEN a.AtribuidoAId IS NULL THEN N'(Sin responsable)' ELSE a.AtribuidoAId END) AS AtribuidoA,
    COALESCE(w.MetodoAtribucion, CASE WHEN u.TipoCuenta = 'app' THEN 'responsable_actual' ELSE 'autor' END) AS MetodoAtribucion,
    w.Inicio, CAST(w.Inicio AS date) AS Fecha, w.Segundos, CAST(w.Segundos / 3600.0 AS decimal(12,2)) AS Horas
FROM ops.Worklog w
JOIN rpt.vIssue i ON i.FuenteId = w.FuenteId AND i.IssueId = w.IssueId
LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
CROSS APPLY (SELECT CASE WHEN w.MetodoAtribucion IS NOT NULL THEN w.AtribuidoAId
                         WHEN u.TipoCuenta = 'app' THEN i.ResponsableId ELSE w.AutorId END AS AtribuidoAId) a
LEFT JOIN ops.Usuario ua ON ua.FuenteId = w.FuenteId AND ua.AccountId = a.AtribuidoAId
WHERE w.Eliminado = 0;
GO
