/* Mueve un widget un lugar antes (-1) o después (1) en su tablero. */
CREATE OR ALTER PROCEDURE api.Widget_Mover
    @WidgetId      int,
    @Direccion     int,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    DECLARE @TableroId int, @orden int;
    SELECT @TableroId = w.TableroId, @orden = w.Orden FROM dash.Widget w JOIN dash.Tablero t ON t.TableroId = w.TableroId
    WHERE w.WidgetId = @WidgetId AND t.PropietarioId = @UsuarioId;
    IF @TableroId IS NULL THROW 50403, 'Solo el propietario del tablero puede ordenar sus widgets.', 1;

    DECLARE @otro int, @ordenOtro int;
    SELECT TOP (1) @otro = WidgetId, @ordenOtro = Orden FROM dash.Widget
    WHERE TableroId = @TableroId AND ((@Direccion < 0 AND Orden < @orden) OR (@Direccion > 0 AND Orden > @orden))
    ORDER BY CASE WHEN @Direccion < 0 THEN -Orden ELSE Orden END;
    IF @otro IS NOT NULL
    BEGIN
        BEGIN TRAN;
        UPDATE dash.Widget SET Orden = @ordenOtro WHERE WidgetId = @WidgetId;
        UPDATE dash.Widget SET Orden = @orden WHERE WidgetId = @otro;
        COMMIT;
    END;
    SELECT 1 AS Movidos;
END;
GO
