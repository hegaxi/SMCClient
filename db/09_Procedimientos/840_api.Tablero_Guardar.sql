/* Crea o modifica un tablero y con quién se comparte (reemplaza la lista).
   @CompartirCon: usuarios y roles separados por coma, p. ej. "ana, mbravo, rol:Consulta". Solo el propietario lo modifica. */
CREATE OR ALTER PROCEDURE api.Tablero_Guardar
    @TableroId     int = NULL,
    @Nombre        nvarchar(150),
    @Descripcion   nvarchar(400) = NULL,
    @CompartirCon  nvarchar(1000) = NULL,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF @UsuarioId IS NULL THROW 50401, 'Usuario no válido.', 1;
    IF @Nombre = N'' THROW 50400, 'El nombre del tablero es obligatorio.', 1;
    IF @TableroId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dash.Tablero WHERE TableroId = @TableroId AND PropietarioId = @UsuarioId)
        THROW 50403, 'Solo el propietario puede modificar el tablero.', 1;
    IF EXISTS (SELECT 1 FROM dash.Tablero WHERE PropietarioId = @UsuarioId AND Nombre = @Nombre AND TableroId <> ISNULL(@TableroId, -1))
        THROW 50409, 'Ya tiene un tablero con ese nombre.', 1;

    DECLARE @destinos TABLE (Texto nvarchar(200), Tipo char(1), Id int);
    INSERT @destinos (Texto, Tipo, Id)
    SELECT x.Texto,
           CASE WHEN x.Texto LIKE N'rol:%' THEN 'R' ELSE 'U' END,
           CASE WHEN x.Texto LIKE N'rol:%' THEN (SELECT RolId FROM seg.Rol WHERE Nombre = LTRIM(SUBSTRING(x.Texto, 5, 200)))
                ELSE (SELECT UsuarioId FROM seg.Usuario WHERE Login = x.Texto) END
    FROM (SELECT DISTINCT LTRIM(RTRIM(value)) AS Texto FROM STRING_SPLIT(ISNULL(@CompartirCon, N''), ',') WHERE LTRIM(RTRIM(value)) <> N'') x;

    DECLARE @msg nvarchar(1000) = (SELECT STRING_AGG(Texto, N', ') FROM @destinos WHERE Id IS NULL);
    IF @msg IS NOT NULL
    BEGIN
        SET @msg = N'No existen: ' + @msg + N'. Use el nombre de usuario o rol:NombreDelRol.';
        THROW 50400, @msg, 1;
    END;

    BEGIN TRAN;
    IF @TableroId IS NULL
    BEGIN
        INSERT dash.Tablero (Nombre, Descripcion, PropietarioId) VALUES (@Nombre, @Descripcion, @UsuarioId);
        SET @TableroId = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dash.Tablero SET Nombre = @Nombre, Descripcion = @Descripcion, FechaCambio = SYSDATETIMEOFFSET() WHERE TableroId = @TableroId;

    DELETE dash.TableroCompartido WHERE TableroId = @TableroId;
    INSERT dash.TableroCompartido (TableroId, Tipo, Id)
    SELECT DISTINCT @TableroId, Tipo, Id FROM @destinos WHERE NOT (Tipo = 'U' AND Id = @UsuarioId);
    COMMIT;

    SELECT @TableroId AS TableroId;
END;
GO
