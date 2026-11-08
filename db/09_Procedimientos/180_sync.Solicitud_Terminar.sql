CREATE OR ALTER PROCEDURE sync.Solicitud_Terminar
    @SolicitudId bigint,
    @Estado      varchar(15) = 'hecha'
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE sync.Solicitud SET Estado = @Estado, TerminadaEn = SYSDATETIMEOFFSET() WHERE SolicitudId = @SolicitudId;
END;
GO
