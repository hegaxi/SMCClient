/* Pide una sincronización (botón "Sincronizar ahora"). No duplica si ya hay una pendiente igual. */
CREATE OR ALTER PROCEDURE api.Sync_Solicitar
    @Fuente        varchar(50) = NULL,
    @SolicitadoPor nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @Fuente IS NOT NULL AND @FuenteId IS NULL THROW 50100, 'La fuente no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM sync.Solicitud WHERE Estado IN ('pendiente', 'tomada') AND Modo = 'incremental'
                   AND ISNULL(FuenteId, -1) = ISNULL(@FuenteId, -1) AND Entidad IS NULL)
        INSERT sync.Solicitud (FuenteId, Entidad, Modo, SolicitadoPor) VALUES (@FuenteId, NULL, 'incremental', @SolicitadoPor);

    SELECT TOP (1) SolicitudId, Estado, Fecha FROM sync.Solicitud
    WHERE Modo = 'incremental' AND ISNULL(FuenteId, -1) = ISNULL(@FuenteId, -1) AND Entidad IS NULL
    ORDER BY SolicitudId DESC;
END;
GO
