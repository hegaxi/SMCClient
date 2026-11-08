/* Cierra una solicitud ('hecha' o 'error') o la devuelve a la cola ('pendiente'), por ejemplo
   cuando otra instancia tenía el candado de la fuente. */
CREATE OR ALTER PROCEDURE sync.Solicitud_Terminar
    @SolicitudId bigint,
    @Estado      varchar(15) = 'hecha'
AS
BEGIN
    SET NOCOUNT ON;
    IF @Estado NOT IN ('hecha', 'error', 'pendiente') THROW 50080, 'Estado de solicitud inválido.', 1;
    UPDATE sync.Solicitud
    SET Estado = @Estado,
        TomadaEn = CASE WHEN @Estado = 'pendiente' THEN NULL ELSE TomadaEn END,
        TerminadaEn = CASE WHEN @Estado = 'pendiente' THEN NULL ELSE SYSDATETIMEOFFSET() END
    WHERE SolicitudId = @SolicitudId;
END;
GO
