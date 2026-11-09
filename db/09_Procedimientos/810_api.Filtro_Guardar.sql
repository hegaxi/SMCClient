/* Crea o modifica un filtro guardado. Reglas:
   - Solo el propietario lo modifica.
   - La consulta debe existir, estar permitida para el usuario y no ser una acción (smc:accion).
   - Cada parámetro del JSON debe existir en la consulta (no se aceptan los que llena el servidor).
   - Los valores {hoy}, {hoy-30}, {inicio_mes}... se guardan tal cual y se resuelven al usarse. */
CREATE OR ALTER PROCEDURE api.Filtro_Guardar
    @FiltroId      int = NULL,
    @Nombre        nvarchar(150),
    @Procedimiento sysname,
    @Parametros    nvarchar(max) = N'{}',
    @Compartido    bit = 0,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    SET @Procedimiento = REPLACE(LTRIM(RTRIM(@Procedimiento)), N'api.', N'');
    SET @Parametros = ISNULL(NULLIF(LTRIM(RTRIM(@Parametros)), N''), N'{}');
    IF @UsuarioId IS NULL THROW 50401, 'Usuario no válido.', 1;
    IF @Nombre = N'' THROW 50400, 'El nombre del filtro es obligatorio.', 1;
    IF ISJSON(@Parametros) = 0 OR LEFT(LTRIM(@Parametros), 1) <> N'{' THROW 50400, 'Los parámetros deben ser un objeto JSON.', 1;

    DECLARE @objeto int = OBJECT_ID(N'api.' + QUOTENAME(@Procedimiento), 'P');
    IF @objeto IS NULL THROW 50404, 'La consulta no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@UsuarioId) WHERE Procedimiento = @Procedimiento)
        THROW 50403, 'No tiene permiso para esa consulta.', 1;
    IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = @objeto AND minor_id = 0 AND name = 'smc:accion' AND CAST(value AS nvarchar(10)) = N'1')
        THROW 50400, 'Solo se pueden guardar filtros de consultas, no de acciones.', 1;

    DECLARE @msg nvarchar(1000) = (
        SELECT STRING_AGG(k.Clave, N', ')
        FROM OPENJSON(@Parametros) j
        CROSS APPLY (SELECT REPLACE(j.[key], N'@', N'') COLLATE DATABASE_DEFAULT AS Clave) k   -- OPENJSON devuelve [key] en BIN2
        WHERE k.Clave IN (N'UsuarioActual', N'SolicitadoPor')
           OR NOT EXISTS (SELECT 1 FROM sys.parameters p WHERE p.object_id = @objeto AND p.name = N'@' + k.Clave));
    IF @msg IS NOT NULL
    BEGIN
        SET @msg = N'La consulta no tiene estos parámetros: ' + @msg + N'.';
        THROW 50400, @msg, 1;
    END;

    IF @FiltroId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dash.Filtro WHERE FiltroId = @FiltroId AND PropietarioId = @UsuarioId)
        THROW 50403, 'Solo el propietario puede modificar el filtro.', 1;
    IF EXISTS (SELECT 1 FROM dash.Filtro WHERE PropietarioId = @UsuarioId AND Nombre = @Nombre AND FiltroId <> ISNULL(@FiltroId, -1))
        THROW 50409, 'Ya tiene un filtro con ese nombre.', 1;

    IF @FiltroId IS NULL
    BEGIN
        INSERT dash.Filtro (Nombre, Procedimiento, Parametros, PropietarioId, Compartido)
        VALUES (@Nombre, @Procedimiento, @Parametros, @UsuarioId, @Compartido);
        SET @FiltroId = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dash.Filtro SET Nombre = @Nombre, Procedimiento = @Procedimiento, Parametros = @Parametros, Compartido = @Compartido,
                               FechaCambio = SYSDATETIMEOFFSET()
        WHERE FiltroId = @FiltroId;

    SELECT @FiltroId AS FiltroId;
END;
GO
