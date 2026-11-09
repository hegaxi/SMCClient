CREATE OR ALTER PROCEDURE api.Tablero_Eliminar
    @TableroId     int,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    DECLARE @propietario int = (SELECT PropietarioId FROM dash.Tablero WHERE TableroId = @TableroId);
    IF @propietario IS NULL THROW 50404, 'El tablero no existe.', 1;
    IF @propietario <> @UsuarioId AND seg.fn_EsAdministrador(@UsuarioId) = 0 THROW 50403, 'Solo el propietario puede eliminar el tablero.', 1;
    DELETE dash.Tablero WHERE TableroId = @TableroId;   -- widgets, compartidos y preferencias en cascada
    SELECT 1 AS Eliminados;
END;
GO
