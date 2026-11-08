CREATE OR ALTER PROCEDURE api.Widget_Eliminar
    @WidgetId      int,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF NOT EXISTS (SELECT 1 FROM dash.Widget w JOIN dash.Tablero t ON t.TableroId = w.TableroId WHERE w.WidgetId = @WidgetId AND t.PropietarioId = @UsuarioId)
        THROW 50403, 'Solo el propietario del tablero puede quitar widgets.', 1;
    DELETE dash.Widget WHERE WidgetId = @WidgetId;
    SELECT 1 AS Eliminados;
END;
GO
