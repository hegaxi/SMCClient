/* Calcula y guarda el ORIGEN de los worklogs y la persona a la que se ATRIBUYEN (antes se calculaba en rpt.vWorklog
   en cada consulta). Se llama al integrar worklogs, historial o issues (sync.Derivados_Actualizar), solo para los
   issues tocados; @Todo = 1 recalcula toda la fuente.
   Origen: 'manual' si lo registró una persona; 'automatico' si lo registró una app (accountType = app,
   p. ej. Automation for Jira, que en smco registra 1 día por cada día hábil que el issue sigue abierto).
   Atribución:
     manual      -> el autor.
     automatico  -> el responsable del issue el día del worklog, según el historial de cambios del campo assignee:
                    el último cambio hasta esa fecha; si no hubo cambios antes, el responsable "desde" del primer cambio
                    posterior; si nunca cambió, el responsable actual. NULL = el issue no tenía responsable ese día. */
CREATE OR ALTER PROCEDURE sync.Worklog_Atribuir
    @FuenteId int,
    @Issues   sync.IdTipo READONLY,
    @Todo     bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE w SET EsAutomatico = x.EsAutomatico, AtribuidoAId = x.AtribuidoAId, MetodoAtribucion = x.Metodo
    FROM ops.Worklog w
    JOIN ops.Issue i ON i.FuenteId = w.FuenteId AND i.IssueId = w.IssueId
    LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
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
    OUTER APPLY (SELECT TOP (1) 1 AS Hay FROM ops.IssueCambio c WHERE c.IssueSk = i.IssueSk AND c.CampoId = 'assignee') historial
    OUTER APPLY (SELECT TOP (1) 1 AS Hay FROM ops.IssueCambio c WHERE c.IssueSk = i.IssueSk AND c.CampoId = 'assignee' AND c.Fecha <= w.Inicio) previo
    CROSS APPLY (
        SELECT CAST(CASE WHEN u.TipoCuenta = 'app' THEN 1 ELSE 0 END AS bit) AS EsAutomatico,
               CASE WHEN ISNULL(u.TipoCuenta, '') <> 'app' THEN w.AutorId
                    WHEN historial.Hay IS NULL THEN i.ResponsableId
                    WHEN previo.Hay IS NOT NULL THEN antes.Hacia
                    ELSE despues.Desde END AS AtribuidoAId,
               CASE WHEN ISNULL(u.TipoCuenta, '') <> 'app' THEN 'autor'
                    WHEN historial.Hay IS NULL THEN 'responsable_actual'
                    ELSE 'historial' END AS Metodo
    ) x
    WHERE w.FuenteId = @FuenteId
      AND (@Todo = 1 OR w.IssueId IN (SELECT IdExterno FROM @Issues))
      AND (w.EsAutomatico IS NULL OR w.EsAutomatico <> x.EsAutomatico OR w.MetodoAtribucion IS NULL OR w.MetodoAtribucion <> x.Metodo
           OR ISNULL(w.AtribuidoAId, '') <> ISNULL(x.AtribuidoAId, ''));
END;
GO
