/* Elimina un filtro (su propietario o un administrador). No se elimina si algún widget lo usa. */
CREATE OR ALTER PROCEDURE api.Filtro_Eliminar
    @FiltroId      int,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    DECLARE @propietario int = (SELECT PropietarioId FROM dash.Filtro WHERE FiltroId = @FiltroId);
    IF @propietario IS NULL THROW 50404, 'El filtro no existe.', 1;
    IF @propietario <> @UsuarioId AND seg.fn_EsAdministrador(@UsuarioId) = 0 THROW 50403, 'Solo el propietario puede eliminar el filtro.', 1;

    DECLARE @msg nvarchar(1000) = (SELECT STRING_AGG(t.Nombre, N', ') FROM (SELECT DISTINCT t.Nombre FROM dash.Widget w JOIN dash.Tablero t ON t.TableroId = w.TableroId WHERE w.FiltroId = @FiltroId) t);
    IF @msg IS NOT NULL
    BEGIN
        SET @msg = N'El filtro se usa en los tableros: ' + @msg + N'. Quite esos widgets primero.';
        THROW 50409, @msg, 1;
    END;
    DELETE dash.Filtro WHERE FiltroId = @FiltroId;
    SELECT 1 AS Eliminados;
END;
GO
