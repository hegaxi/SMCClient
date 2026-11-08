/* Detalle de un issue: 1) datos canónicos, 2) TODOS los campos extra (formato largo, la interfaz los
   convierte en columnas), 3) worklogs, 4) SLA, 5) historial de estados. */
CREATE OR ALTER PROCEDURE api.Issue_Detalle
    @Clave varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IssueSk bigint = (SELECT TOP (1) IssueSk FROM rpt.vIssue WHERE Clave = @Clave ORDER BY Actualizado DESC);
    IF @IssueSk IS NULL THROW 50120, 'No existe el issue.', 1;

    SELECT Clave, ProyectoClave, ProyectoNombre, TipoProyecto, TipoIssue, TipoSolicitud, Resumen, Estado, CategoriaEstado,
           Prioridad, Resolucion, Responsable, Informante, PadreClave, StoryPoints,
           CAST(TiempoInvertidoSeg / 3600.0 AS decimal(12,2)) AS HorasInvertidas,
           CAST(EstimacionOriginalSeg / 3600.0 AS decimal(12,2)) AS HorasEstimadas,
           CAST(EstimacionRestanteSeg / 3600.0 AS decimal(12,2)) AS HorasRestantes,
           Creado, Actualizado, Resuelto, Vencimiento
    FROM rpt.vIssue WHERE IssueSk = @IssueSk;

    SELECT CampoId, Campo, TipoSchema, CampoActivo, Orden, ValorId, ValorTexto, ValorNumero, ValorFecha, ValorJson
    FROM rpt.vIssueCampoValor WHERE IssueSk = @IssueSk ORDER BY Campo, Orden;

    SELECT WorklogId, Autor, TipoCuentaAutor, Inicio, Horas FROM rpt.vWorklog WHERE IssueSk = @IssueSk ORDER BY Inicio;

    SELECT Sla, Ciclo, EnCurso, Inicio, Fin, Vencimiento, ObjetivoMs, TranscurridoMs, Pausado, Incumplido, MinutosParaVencer
    FROM rpt.vSla WHERE IssueSk = @IssueSk ORDER BY Sla, Ciclo;

    SELECT Fecha, EstadoDesde, EstadoHacia, MinutosEnEstado FROM rpt.vTransicionEstado WHERE IssueSk = @IssueSk ORDER BY Fecha;
END;
GO
