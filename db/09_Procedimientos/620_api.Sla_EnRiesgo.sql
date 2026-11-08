/* Tickets con un SLA en curso que vence en las próximas @Horas (o ya vencido). */
CREATE OR ALTER PROCEDURE api.Sla_EnRiesgo
    @Horas    int = 4,
    @Proyecto varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.Clave, s.ProyectoClave, s.Resumen, s.Prioridad, s.Responsable, s.Sla, s.Vencimiento, s.MinutosParaVencer, s.Incumplido
    FROM rpt.vSla s
    WHERE s.EnCurso = 1 AND s.Pausado = 0 AND s.Abierto = 1
      AND s.MinutosParaVencer <= @Horas * 60
      AND (@Proyecto IS NULL OR s.ProyectoClave = @Proyecto)
    ORDER BY s.MinutosParaVencer;
END;
GO
