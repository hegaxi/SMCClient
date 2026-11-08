/* Guarda una contraseña nueva (ya convertida en hash por la API). Reglas:
   - Longitud mínima (cfg.Parametro ContrasenaLongitudMinima); la API envía solo la longitud, nunca el texto.
   - Cambiar la propia: la API debe haber verificado la contraseña actual (@ActualVerificada = 1).
   - Restablecer la de otro: solo un usuario con permiso 'admin'; el usuario deberá cambiarla al entrar.
   - Cambia el sello de seguridad: se cierran las demás sesiones de ese usuario. */
CREATE OR ALTER PROCEDURE seg.Contrasena_Establecer
    @Login            nvarchar(100),
    @Hash             varbinary(64),
    @Sal              varbinary(32),
    @Iteraciones      int,
    @Longitud         int,
    @UsuarioActual    nvarchar(100),
    @ActualVerificada bit = 0,
    @SelloNuevo       uniqueidentifier = NULL OUTPUT
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
    IF @Iteraciones < 100000 THROW 50400, 'Parámetros de hash inválidos.', 1;
    IF NOT EXISTS (SELECT 1 FROM seg.Usuario WHERE Login = @Login) THROW 50404, 'El usuario no existe.', 1;

    DECLARE @propia bit = CASE WHEN @Login = @UsuarioActual THEN 1 ELSE 0 END;
    IF @propia = 1 AND @ActualVerificada = 0 THROW 50400, 'Para cambiar su contraseña indique la actual.', 1;
    IF @propia = 0 AND NOT EXISTS (SELECT 1 FROM seg.Usuario u JOIN seg.UsuarioRol ur ON ur.UsuarioId = u.UsuarioId
                                   JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                                   WHERE u.Login = @UsuarioActual AND u.Activo = 1 AND rp.Permiso = N'admin')
        THROW 50403, 'Solo un administrador puede restablecer la contraseña de otro usuario.', 1;

    SET @SelloNuevo = NEWID();
    BEGIN TRAN;
    UPDATE seg.Usuario
    SET ContrasenaHash = @Hash, ContrasenaSal = @Sal, ContrasenaIteraciones = @Iteraciones, ContrasenaFecha = SYSDATETIMEOFFSET(),
        DebeCambiarContrasena = CASE WHEN @propia = 1 THEN 0 ELSE 1 END,
        IntentosFallidos = 0, BloqueadoHasta = NULL, SelloSeguridad = @SelloNuevo
    WHERE Login = @Login;
    DECLARE @accion varchar(60) = CASE WHEN @propia = 1 THEN 'contrasena.cambiar' ELSE 'contrasena.restablecer' END;
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = @accion, @Objeto = @Login;
    COMMIT;
END;
GO
