/* SLA por ticket y ciclo. Para el ciclo en curso, el tiempo restante se recalcula contra la hora
   actual a partir del vencimiento (el RestanteMs guardado es una foto del momento de la sincronización).
   PrioridadItil: la prioridad que fija el objetivo del SLA en JSM (campo mapeado al rol prioridad_itil, p. ej.
   "prioridad" 1-5 calculada con urgencia x impacto); la Prioridad de Jira casi siempre queda en "Medium". */
CREATE OR ALTER VIEW rpt.vSla
AS
SELECT
    i.IssueSk, i.FuenteId, i.Clave, i.ProyectoClave, i.Resumen, i.Prioridad, i.Responsable, i.Abierto, i.Creado,
    CAST(pi.ValorNumero AS int) AS PrioridadItil,
    s.SlaId, s.Nombre AS Sla, s.Ciclo, s.EnCurso, s.Inicio, s.Fin, s.Vencimiento,
    s.ObjetivoMs, s.TranscurridoMs, s.Pausado, s.EnHorarioLaboral,
    CAST(CASE
        WHEN s.Incumplido = 1 THEN 1
        WHEN s.EnCurso = 1 AND s.Pausado = 0 AND s.Vencimiento < SYSDATETIMEOFFSET() THEN 1
        ELSE 0 END AS bit) AS Incumplido,
    CASE WHEN s.EnCurso = 1 AND s.Pausado = 0 AND s.Vencimiento IS NOT NULL
         THEN DATEDIFF(MINUTE, SYSDATETIMEOFFSET(), s.Vencimiento) END AS MinutosParaVencer
FROM ops.IssueSla s
JOIN rpt.vIssue i ON i.IssueSk = s.IssueSk
LEFT JOIN cfg.MapeoCampo mp ON mp.FuenteId = i.FuenteId AND mp.Rol = 'prioridad_itil'
LEFT JOIN ops.IssueCampoValor pi ON pi.IssueSk = i.IssueSk AND pi.CampoId = mp.CampoId AND pi.Orden = 0;
GO
