/* Un tablero para mostrarlo: 1) datos del tablero, 2) sus widgets con la consulta y los parámetros YA RESUELTOS
   (fechas relativas convertidas a la fecha de hoy) y si quien lo ve puede ejecutar esa consulta.
   Los datos de cada widget se obtienen ejecutando su consulta con los permisos de quien ve el tablero. */
CREATE OR ALTER PROCEDURE api.Tablero_Obtener
    @TableroId     int,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF NOT EXISTS (SELECT 1 FROM dash.Tablero WHERE TableroId = @TableroId) THROW 50404, 'El tablero no existe.', 1;
    IF dash.fn_PuedeVerTablero(@TableroId, @UsuarioId) = 0 THROW 50403, 'No tiene acceso a este tablero.', 1;
    DECLARE @hoy date = CAST(SYSDATETIMEOFFSET() AS date);

    SELECT t.TableroId, t.Nombre, t.Descripcion, u.Nombre AS Propietario,
           CAST(CASE WHEN t.PropietarioId = @UsuarioId THEN 1 ELSE 0 END AS bit) AS EsMio,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM dash.Preferencia p WHERE p.UsuarioId = @UsuarioId AND p.TableroInicioId = t.TableroId) THEN 1 ELSE 0 END AS bit) AS EsInicio
    FROM dash.Tablero t JOIN seg.Usuario u ON u.UsuarioId = t.PropietarioId
    WHERE t.TableroId = @TableroId;

    SELECT w.WidgetId, w.Titulo, w.Tipo, w.Configuracion, w.Ancho, w.Orden,
           f.FiltroId, f.Nombre AS Filtro, f.Procedimiento, f.Parametros,
           dash.fn_ResolverParametros(f.Parametros, @hoy) AS ParametrosResueltos,
           CAST(CASE WHEN pp.Procedimiento IS NOT NULL THEN 1 ELSE 0 END AS bit) AS PuedoEjecutar
    FROM dash.Widget w
    JOIN dash.Filtro f ON f.FiltroId = w.FiltroId
    LEFT JOIN seg.fn_ProcedimientosPermitidos(@UsuarioId) pp ON pp.Procedimiento = f.Procedimiento
    WHERE w.TableroId = @TableroId
    ORDER BY w.Orden, w.WidgetId;
END;
GO
