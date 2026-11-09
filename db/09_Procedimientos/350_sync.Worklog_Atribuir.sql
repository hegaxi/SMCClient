/* Calcula y guarda el ORIGEN de los worklogs y la persona a la que se ATRIBUYEN (antes se calculaba en rpt.vWorklog
   en cada consulta). Se llama al integrar worklogs, historial o issues (sync.Derivados_Actualizar), solo para los
   issues tocados; @Todo = 1 recalcula toda la fuente.
   Origen: 'manual' si lo registró una persona; 'automatico' si lo registró una app (accountType = app,
   p. ej. Automation for Jira). Además marca las COPIAS automáticas (EsCopia, ver abajo).
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

    /* Copias. Automation for Jira (en smco) replica cada worklog que una persona registra en una subtarea hacia su
       tarea, su épica y el ticket de la OC en la mesa de servicio: mismo tiempo, creadas al mismo minuto. Un worklog
       automático es COPIA si:
         - hay un worklog de una persona en OTRO issue con el mismo tiempo, creado hasta 2 h antes o después (es su
           original; si hay varios, el más cercano), o
         - hay otro worklog automático en otro issue con el mismo tiempo creado hasta 2 min antes o después (copias
           hermanas de un original que después se editó o se borró).
       Las copias no se suman en los reportes (el trabajo ya está en el original). Los registrados por personas nunca
       son copia. En smco, 712 de 714 worklogs automáticos resultaron copias. */
    SELECT w.WorklogId,
           CAST(CASE WHEN w.EsAutomatico = 1 AND (o.WorklogId IS NOT NULL OR h.Hay IS NOT NULL) THEN 1 ELSE 0 END AS bit) AS EsCopia,
           CASE WHEN w.EsAutomatico = 1 THEN o.WorklogId END AS CopiaDe
    INTO #copia
    FROM ops.Worklog w
    OUTER APPLY (
        SELECT TOP (1) m.WorklogId FROM ops.Worklog m
        WHERE w.EsAutomatico = 1 AND m.FuenteId = w.FuenteId AND m.Segundos = w.Segundos
          AND m.Creado BETWEEN DATEADD(hour, -2, w.Creado) AND DATEADD(hour, 2, w.Creado)
          AND m.IssueId <> w.IssueId AND m.Eliminado = 0 AND m.EsAutomatico = 0
        ORDER BY ABS(DATEDIFF(second, m.Creado, w.Creado)), m.WorklogId
    ) o
    OUTER APPLY (
        SELECT TOP (1) 1 AS Hay FROM ops.Worklog m
        WHERE w.EsAutomatico = 1 AND o.WorklogId IS NULL AND m.FuenteId = w.FuenteId AND m.Segundos = w.Segundos
          AND m.Creado BETWEEN DATEADD(minute, -2, w.Creado) AND DATEADD(minute, 2, w.Creado)
          AND m.IssueId <> w.IssueId AND m.Eliminado = 0 AND m.EsAutomatico = 1
    ) h
    WHERE w.FuenteId = @FuenteId
      AND (@Todo = 1 OR w.IssueId IN (SELECT IdExterno FROM @Issues));

    UPDATE w SET EsCopia = c.EsCopia, CopiaDeWorklogId = c.CopiaDe
    FROM ops.Worklog w JOIN #copia c ON c.WorklogId = w.WorklogId
    WHERE w.FuenteId = @FuenteId
      AND (w.EsCopia IS NULL OR w.EsCopia <> c.EsCopia OR ISNULL(w.CopiaDeWorklogId, '') <> ISNULL(c.CopiaDe, ''));
END;
GO
