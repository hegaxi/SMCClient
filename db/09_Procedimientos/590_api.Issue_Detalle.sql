/* Detalle de un issue: 1) datos canónicos, 2) TODOS los campos extra (formato largo, la interfaz los
   convierte en columnas), 3) worklogs (también los de sus subtareas: en Scrum ahí se registra el tiempo),
   4) SLA, 5) historial de estados. */
CREATE OR ALTER PROCEDURE api.Issue_Detalle
    @Clave varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IssueSk bigint = (SELECT TOP (1) IssueSk FROM rpt.vIssue WHERE Clave = @Clave ORDER BY Actualizado DESC);
    IF @IssueSk IS NULL THROW 50404, 'No existe el issue.', 1;

    SELECT Clave, ProyectoClave, ProyectoNombre, TipoProyecto, TipoIssue, TipoSolicitud, Resumen, Estado, CategoriaEstado,
           Prioridad, Resolucion, Responsable, Informante, PadreClave, StoryPoints,
           CAST(TiempoInvertidoSeg / 3600.0 AS decimal(12,2)) AS HorasInvertidas,
           CAST(EstimacionOriginalSeg / 3600.0 AS decimal(12,2)) AS HorasEstimadas,
           CAST(EstimacionRestanteSeg / 3600.0 AS decimal(12,2)) AS HorasRestantes,
           h.HorasRegistradas AS HorasRegistradasConSubtareas, h.HorasAutomaticas AS HorasAutomaticasConSubtareas,
           Creado, Actualizado, Resuelto, Vencimiento
    FROM rpt.vIssue i
    OUTER APPLY rpt.fn_HorasIssue(i.FuenteId, i.IssueId, i.Clave) h
    WHERE i.IssueSk = @IssueSk;

    SELECT CampoId, Campo, TipoSchema, CampoActivo, Orden, ValorId, ValorTexto, ValorNumero, ValorFecha, ValorJson
    FROM rpt.vIssueCampoValor WHERE IssueSk = @IssueSk ORDER BY Campo, Orden;

    SELECT w.Clave, w.WorklogId, w.Inicio, w.Horas, w.Origen, w.AtribuidoA, w.MetodoAtribucion, w.Autor
    FROM rpt.vWorklog w
    WHERE w.IssueSk = @IssueSk
       OR w.IssueSk IN (SELECT s.IssueSk FROM ops.Issue s JOIN ops.Issue p ON p.IssueSk = @IssueSk
                        WHERE s.FuenteId = p.FuenteId AND s.PadreClave = p.Clave AND s.EsSubtarea = 1 AND s.Eliminado = 0)
    ORDER BY w.Inicio;

    SELECT Sla, Ciclo, EnCurso, Inicio, Fin, Vencimiento, ObjetivoMs, TranscurridoMs, Pausado, Incumplido, MinutosParaVencer
    FROM rpt.vSla WHERE IssueSk = @IssueSk ORDER BY Sla, Ciclo;

    SELECT Fecha, EstadoDesde, EstadoHacia, MinutosEnEstado FROM rpt.vTransicionEstado WHERE IssueSk = @IssueSk ORDER BY Fecha;
END;
GO
