/* Conciliación de borrados (diaria): el worker envía TODOS los ids vigentes de un proyecto
   (JQL "project = X" con fields=id). Los que ya no están se marcan Eliminado = 1.
   Protección: si llegan menos del umbral de los ids activos no se marca nada, salvo @Forzar = 1. */
CREATE OR ALTER PROCEDURE sync.Issue_ConciliarIds
    @EjecucionId bigint,
    @ProyectoId  varchar(30),
    @Ids         sync.IdTipo READONLY,
    @Forzar      bit = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM sync.Ejecucion WHERE EjecucionId = @EjecucionId);
    IF @FuenteId IS NULL THROW 50060, 'La ejecución no existe.', 1;

    DECLARE @umbral int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'UmbralBajaCatalogoPct') AS int), 50);
    DECLARE @recibidos int = (SELECT COUNT(*) FROM @Ids);
    DECLARE @activos int = (SELECT COUNT(*) FROM ops.Issue WHERE FuenteId = @FuenteId AND ProyectoId = @ProyectoId AND Eliminado = 0);

    IF @Forzar = 0 AND @activos > 0 AND @recibidos * 100 < @activos * @umbral
    BEGIN
        DECLARE @msg nvarchar(1000) = CONCAT(N'Conciliación del proyecto ', @ProyectoId, N' omitida: llegaron ', @recibidos, N' ids de ', @activos, N' activos.');
        EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'issue.conciliacion_omitida', @msg;
        SELECT 0 AS Eliminados;
        RETURN;
    END;

    UPDATE i SET Eliminado = 1, Integrado = SYSDATETIMEOFFSET()
    FROM ops.Issue i
    WHERE i.FuenteId = @FuenteId AND i.ProyectoId = @ProyectoId AND i.Eliminado = 0
      AND NOT EXISTS (SELECT 1 FROM @Ids x WHERE x.IdExterno = i.IssueId);
    SELECT @@ROWCOUNT AS Eliminados;
END;
GO
