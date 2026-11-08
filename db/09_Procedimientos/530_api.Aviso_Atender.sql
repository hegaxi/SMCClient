CREATE OR ALTER PROCEDURE api.Aviso_Atender
    @EventoId bigint
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE sync.Evento SET Atendido = 1 WHERE EventoId = @EventoId;
    SELECT @@ROWCOUNT AS Atendidos;
END;
GO
