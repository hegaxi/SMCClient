/* Agrega o modifica un widget (solo el propietario del tablero). El filtro debe poder usarlo el propietario
   (suyo, o compartido de una consulta que tiene permitida). */
CREATE OR ALTER PROCEDURE api.Widget_Guardar
    @WidgetId      int = NULL,
    @TableroId     int,
    @Titulo        nvarchar(150),
    @FiltroId      int,
    @Tipo          varchar(12),
    @Configuracion nvarchar(max) = N'{}',
    @Ancho         tinyint = 2,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    SET @Titulo = LTRIM(RTRIM(@Titulo));
    SET @Configuracion = ISNULL(NULLIF(LTRIM(RTRIM(@Configuracion)), N''), N'{}');
    IF NOT EXISTS (SELECT 1 FROM dash.Tablero WHERE TableroId = @TableroId) THROW 50404, 'El tablero no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dash.Tablero WHERE TableroId = @TableroId AND PropietarioId = @UsuarioId)
        THROW 50403, 'Solo el propietario del tablero puede modificar sus widgets.', 1;
    IF @WidgetId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dash.Widget WHERE WidgetId = @WidgetId AND TableroId = @TableroId)
        THROW 50404, 'El widget no existe en este tablero.', 1;
    IF @Titulo = N'' THROW 50400, 'El título es obligatorio.', 1;
    IF @Tipo NOT IN ('indicador', 'tabla', 'barras') THROW 50400, 'Tipo de widget inválido: indicador, tabla o barras.', 1;
    IF @Ancho NOT BETWEEN 1 AND 4 THROW 50400, 'El ancho va de 1 a 4 columnas.', 1;
    IF ISJSON(@Configuracion) = 0 THROW 50400, 'La configuración debe ser JSON.', 1;
    IF @Tipo = 'barras' AND (JSON_VALUE(@Configuracion, '$.etiqueta') IS NULL OR JSON_VALUE(@Configuracion, '$.valor') IS NULL)
        THROW 50400, 'Un widget de barras necesita la columna de etiqueta y la de valor.', 1;
    IF @Tipo = 'indicador' AND JSON_VALUE(@Configuracion, '$.agregacion') NOT IN ('suma', 'promedio', 'conteo', 'maximo', 'minimo', 'primero')
        THROW 50400, 'Agregación inválida: suma, promedio, conteo, maximo, minimo o primero.', 1;
    IF @Tipo = 'indicador' AND ISNULL(JSON_VALUE(@Configuracion, '$.agregacion'), 'conteo') <> 'conteo' AND JSON_VALUE(@Configuracion, '$.columna') IS NULL
        THROW 50400, 'El indicador necesita la columna a calcular.', 1;

    DECLARE @procFiltro sysname, @propFiltro int, @compartido bit;
    SELECT @procFiltro = Procedimiento, @propFiltro = PropietarioId, @compartido = Compartido FROM dash.Filtro WHERE FiltroId = @FiltroId;
    IF @procFiltro IS NULL THROW 50404, 'El filtro no existe.', 1;
    IF NOT (@propFiltro = @UsuarioId OR (@compartido = 1 AND EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@UsuarioId) WHERE Procedimiento = @procFiltro)))
        THROW 50403, 'No puede usar ese filtro.', 1;

    IF @WidgetId IS NULL
    BEGIN
        INSERT dash.Widget (TableroId, Titulo, FiltroId, Tipo, Configuracion, Ancho, Orden)
        VALUES (@TableroId, @Titulo, @FiltroId, @Tipo, @Configuracion, @Ancho,
                ISNULL((SELECT MAX(Orden) FROM dash.Widget WHERE TableroId = @TableroId), 0) + 1);
        SET @WidgetId = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dash.Widget SET Titulo = @Titulo, FiltroId = @FiltroId, Tipo = @Tipo, Configuracion = @Configuracion, Ancho = @Ancho
        WHERE WidgetId = @WidgetId;

    UPDATE dash.Tablero SET FechaCambio = SYSDATETIMEOFFSET() WHERE TableroId = @TableroId;
    SELECT @WidgetId AS WidgetId;
END;
GO
