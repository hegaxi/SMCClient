/* Detalle de un issue: 1) datos canónicos, 2) TODOS los campos extra (formato largo, la interfaz los
   convierte en columnas), 3) worklogs (también los de sus descendientes: subtareas de una tarea; tareas y subtareas
   de una épica; en Scrum las personas registran en las subtareas),
   4) SLA, 5) historial de estados. */
CREATE OR ALTER PROCEDURE api.Issue_Detalle
    @Clave varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IssueSk bigint = (SELECT TOP (1) IssueSk FROM rpt.vIssue WHERE Clave = @Clave ORDER BY Actualizado DESC);
    IF @IssueSk IS NULL THROW 50404, 'No existe el issue.', 1;

    SELECT Clave, ProyectoClave, ProyectoNombre, TipoProyecto, TipoIssue, TipoSolicitud, Resumen, Estado, CategoriaEstado,
           Prioridad, Resolucion, Responsable, Informante,
           COALESCE((SELECT p.Clave FROM ops.Issue p WHERE p.FuenteId = i.FuenteId AND p.IssueId = i.PadreId), i.PadreClave) AS PadreClave, e.Epica, StoryPoints,
           CAST(TiempoInvertidoSeg / 3600.0 AS decimal(12,2)) AS HorasInvertidas,
           CAST(EstimacionOriginalSeg / 3600.0 AS decimal(12,2)) AS HorasEstimadas,
           CAST(EstimacionRestanteSeg / 3600.0 AS decimal(12,2)) AS HorasRestantes,
           h.HorasRegistradas AS HorasRegistradasConHijos, h.HorasAutomaticas AS HorasAutomaticasConHijos,
           Creado, Actualizado, Resuelto, Vencimiento
    FROM rpt.vIssue i
    OUTER APPLY rpt.fn_HorasIssue(i.FuenteId, i.IssueId, i.Clave) h
    OUTER APPLY rpt.fn_EpicaIssue(i.FuenteId, i.IssueId, i.PadreId, i.NivelJerarquia) e
    WHERE i.IssueSk = @IssueSk;

    SELECT CampoId, Campo, TipoSchema, CampoActivo, Orden, ValorId, ValorTexto, ValorNumero, ValorFecha, ValorJson
    FROM rpt.vIssueCampoValor WHERE IssueSk = @IssueSk ORDER BY Campo, Orden;

    WITH arbol AS (
        SELECT IssueSk, FuenteId, IssueId, 0 AS Nivel FROM ops.Issue WHERE IssueSk = @IssueSk
        UNION ALL
        SELECT h.IssueSk, h.FuenteId, h.IssueId, a.Nivel + 1
        FROM arbol a JOIN ops.Issue h ON h.FuenteId = a.FuenteId AND h.PadreId = a.IssueId
        WHERE h.Eliminado = 0 AND a.Nivel < 5
    )
    SELECT w.Clave, w.WorklogId, w.Inicio, w.Horas, w.Origen, w.AtribuidoA, w.MetodoAtribucion, w.Autor
    FROM arbol a
    JOIN rpt.vWorklog w ON w.FuenteId = a.FuenteId AND w.IssueId = a.IssueId
    ORDER BY w.Inicio;

    SELECT Sla, Ciclo, EnCurso, Inicio, Fin, Vencimiento, ObjetivoMs, TranscurridoMs, Pausado, Incumplido, MinutosParaVencer
    FROM rpt.vSla WHERE IssueSk = @IssueSk ORDER BY Sla, Ciclo;

    SELECT Fecha, EstadoDesde, EstadoHacia, MinutosEnEstado FROM rpt.vTransicionEstado WHERE IssueSk = @IssueSk ORDER BY Fecha;
END;
GO
