/* Crea (o recupera) un administrador con su contraseña. Lo usa el comando
   "dotnet SMCClient.Api.dll crear-administrador", con una conexión de administrador de la base:
   este procedimiento NO está permitido para el rol smc_api, así que la aplicación web no puede llamarlo. */
CREATE OR ALTER PROCEDURE seg.Instalacion_CrearAdministrador
    @Login       nvarchar(100),
    @Nombre      nvarchar(200),
    @Hash        varbinary(64),
    @Sal         varbinary(32),
    @Iteraciones int,
    @Longitud    int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @min int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'ContrasenaLongitudMinima') AS int), 10);
    DECLARE @msg nvarchar(200);
    IF @Longitud < @min
    BEGIN
        SET @msg = CONCAT(N'La contraseña debe tener al menos ', @min, N' caracteres.');
        THROW 50400, @msg, 1;
    END;
    DECLARE @RolId int = (SELECT RolId FROM seg.Rol WHERE Nombre = N'Administrador');
    IF @RolId IS NULL THROW 50500, 'Falta el rol Administrador (¿se ejecutaron los datos semilla?).', 1;

    BEGIN TRAN;
    IF EXISTS (SELECT 1 FROM seg.Usuario WHERE Login = @Login)
        UPDATE seg.Usuario SET Nombre = @Nombre, Activo = 1 WHERE Login = @Login;
    ELSE
        INSERT seg.Usuario (Login, Nombre) VALUES (@Login, @Nombre);
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @Login);
    UPDATE seg.Usuario
    SET ContrasenaHash = @Hash, ContrasenaSal = @Sal, ContrasenaIteraciones = @Iteraciones, ContrasenaFecha = SYSDATETIMEOFFSET(),
        DebeCambiarContrasena = 0, IntentosFallidos = 0, BloqueadoHasta = NULL, SelloSeguridad = NEWID()
    WHERE UsuarioId = @UsuarioId;
    IF NOT EXISTS (SELECT 1 FROM seg.UsuarioRol WHERE UsuarioId = @UsuarioId AND RolId = @RolId)
        INSERT seg.UsuarioRol (UsuarioId, RolId) VALUES (@UsuarioId, @RolId);
    EXEC seg.Auditoria_Registrar @Usuario = N'(instalación)', @Accion = 'usuario.administrador_instalacion', @Objeto = @Login;
    COMMIT;
END;
GO
