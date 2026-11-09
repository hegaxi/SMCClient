/* Cola de SLA para el coordinador de la mesa: ciclos en curso (no pausados, ticket abierto) que vencen en las próximas
   @Horas (Por vencer) o que vencieron en los últimos @DiasVencido días (Vencido). Lo vencido hace más tiempo ya no es
   accionable y llenaba la lista (tickets de hace meses en proyectos de prueba). Primero lo que está por vencer.
   PrioridadItil: la que fija el objetivo del SLA (ver rpt.vSla). */
CREATE OR ALTER PROCEDURE api.Sla_EnRiesgo
    @Horas       int = 4,
    @Proyecto    varchar(50) = NULL,
    @DiasVencido int = 7
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CASE WHEN s.MinutosParaVencer < 0 THEN N'Vencido' ELSE N'Por vencer' END AS Situacion,
           s.Clave, s.ProyectoClave AS Proyecto, s.Resumen, s.PrioridadItil, s.Prioridad, s.Responsable, s.Sla, s.Vencimiento,
           rpt.fn_DuracionTexto(s.MinutosParaVencer) AS TiempoParaVencer,
           DATEDIFF(DAY, s.Creado, SYSDATETIMEOFFSET()) AS DiasAbierto
    FROM rpt.vSla s
    WHERE s.EnCurso = 1 AND s.Pausado = 0 AND s.Abierto = 1
      AND s.MinutosParaVencer <= @Horas * 60
      AND s.MinutosParaVencer >= -@DiasVencido * 1440
      AND (@Proyecto IS NULL OR s.ProyectoClave = @Proyecto)
    ORDER BY CASE WHEN s.MinutosParaVencer < 0 THEN 1 ELSE 0 END,
             CASE WHEN s.MinutosParaVencer < 0 THEN -s.MinutosParaVencer ELSE s.MinutosParaVencer END;
END;
GO
