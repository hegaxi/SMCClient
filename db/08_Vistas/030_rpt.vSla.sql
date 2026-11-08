/* SLA por ticket y ciclo. Para el ciclo en curso, el tiempo restante se recalcula contra la hora
   actual a partir del vencimiento (el RestanteMs guardado es una foto del momento de la sincronización). */
CREATE OR ALTER VIEW rpt.vSla
AS
SELECT
    i.IssueSk, i.FuenteId, i.Clave, i.ProyectoClave, i.Resumen, i.Prioridad, i.Responsable, i.Abierto,
    s.SlaId, s.Nombre AS Sla, s.Ciclo, s.EnCurso, s.Inicio, s.Fin, s.Vencimiento,
    s.ObjetivoMs, s.TranscurridoMs, s.Pausado, s.EnHorarioLaboral,
    CAST(CASE
        WHEN s.Incumplido = 1 THEN 1
        WHEN s.EnCurso = 1 AND s.Pausado = 0 AND s.Vencimiento < SYSDATETIMEOFFSET() THEN 1
        ELSE 0 END AS bit) AS Incumplido,
    CASE WHEN s.EnCurso = 1 AND s.Pausado = 0 AND s.Vencimiento IS NOT NULL
         THEN DATEDIFF(MINUTE, SYSDATETIMEOFFSET(), s.Vencimiento) END AS MinutosParaVencer
FROM ops.IssueSla s
JOIN rpt.vIssue i ON i.IssueSk = s.IssueSk;
GO
