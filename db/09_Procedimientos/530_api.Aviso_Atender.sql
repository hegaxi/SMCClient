CREATE OR ALTER PROCEDURE api.Aviso_Atender
    @EventoId      bigint,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @objeto nvarchar(200) = (SELECT CONCAT(Codigo, N' #', EventoId) FROM sync.Evento WHERE EventoId = @EventoId AND Atendido = 0);
    IF @objeto IS NULL THROW 50404, 'El aviso no existe o ya fue atendido.', 1;
    BEGIN TRAN;
    UPDATE sync.Evento SET Atendido = 1 WHERE EventoId = @EventoId;
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'aviso.atender', @Objeto = @objeto;
    COMMIT;
    SELECT 1 AS Atendidos;
END;
GO
