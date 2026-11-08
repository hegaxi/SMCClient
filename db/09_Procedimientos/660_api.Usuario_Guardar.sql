/* Alta o cambio de un usuario y sus roles (reemplaza los roles). Reglas:
   - Los roles deben existir.
   - Nadie puede desactivarse ni quitarse la administración a sí mismo.
   - Siempre debe quedar al menos un administrador activo.
   - Todo cambio queda en seg.Auditoria con el antes y el después. */
CREATE OR ALTER PROCEDURE api.Usuario_Guardar
    @Login         nvarchar(100),
    @Nombre        nvarchar(200) = NULL,
    @Activo        bit = 1,
    @Roles         nvarchar(1000),
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @Login = LTRIM(RTRIM(@Login));
    IF @Login = N'' THROW 50400, 'El nombre de usuario es obligatorio.', 1;
    IF @Login LIKE N'%[ /\]%' OR @Login LIKE N'(%' THROW 50400, 'El nombre de usuario no puede tener espacios ni diagonales, ni empezar con paréntesis.', 1;

    DECLARE @listaRoles TABLE (Nombre nvarchar(100) PRIMARY KEY);
    INSERT @listaRoles SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Roles, ',') WHERE LTRIM(RTRIM(value)) <> N'';

    DECLARE @msg nvarchar(400) = (SELECT STRING_AGG(r.Nombre, N', ') FROM @listaRoles r WHERE NOT EXISTS (SELECT 1 FROM seg.Rol x WHERE x.Nombre = r.Nombre));
    IF @msg IS NOT NULL
    BEGIN
        SET @msg = N'No existen los roles: ' + @msg + N'.';
        THROW 50400, @msg, 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM @listaRoles) AND @Activo = 1 THROW 50400, 'Asigne al menos un rol a un usuario activo.', 1;

    IF @Login = @UsuarioActual
       AND (@Activo = 0 OR NOT EXISTS (SELECT 1 FROM @listaRoles r JOIN seg.Rol x ON x.Nombre = r.Nombre JOIN seg.RolPermiso rp ON rp.RolId = x.RolId WHERE rp.Permiso = N'admin'))
       AND EXISTS (SELECT 1 FROM seg.Usuario u JOIN seg.UsuarioRol ur ON ur.UsuarioId = u.UsuarioId JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                   WHERE u.Login = @UsuarioActual AND rp.Permiso = N'admin')
        THROW 50409, 'No puede desactivarse ni quitarse la administración a sí mismo. Pídaselo a otro administrador.', 1;

    DECLARE @antes nvarchar(max) = (SELECT u.Nombre, u.Activo,
                                           (SELECT STRING_AGG(r.Nombre, N',') FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId WHERE ur.UsuarioId = u.UsuarioId) AS Roles
                                    FROM seg.Usuario u WHERE u.Login = @Login FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    BEGIN TRAN;
    IF EXISTS (SELECT 1 FROM seg.Usuario WHERE Login = @Login)
        UPDATE seg.Usuario SET Nombre = COALESCE(NULLIF(LTRIM(RTRIM(@Nombre)), N''), Nombre), Activo = @Activo WHERE Login = @Login;
    ELSE
        INSERT seg.Usuario (Login, Nombre, Activo) VALUES (@Login, COALESCE(NULLIF(LTRIM(RTRIM(@Nombre)), N''), @Login), @Activo);

    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @Login);
    DELETE seg.UsuarioRol WHERE UsuarioId = @UsuarioId;
    INSERT seg.UsuarioRol (UsuarioId, RolId) SELECT @UsuarioId, x.RolId FROM @listaRoles r JOIN seg.Rol x ON x.Nombre = r.Nombre;

    IF seg.fn_AdministradoresActivos() = 0
    BEGIN
        ROLLBACK;
        THROW 50409, 'Debe quedar al menos un administrador activo.', 1;
    END;

    -- Al desactivar a alguien se cierran sus sesiones abiertas.
    IF @Activo = 0 UPDATE seg.Usuario SET SelloSeguridad = NEWID() WHERE UsuarioId = @UsuarioId;

    DECLARE @despues nvarchar(max) = (SELECT u.Nombre, u.Activo, @Roles AS Roles FROM seg.Usuario u WHERE u.UsuarioId = @UsuarioId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'usuario.guardar', @Objeto = @Login, @Antes = @antes, @Despues = @despues;
    COMMIT;

    EXEC api.Usuarios_Listar @Texto = @Login;
END;
GO
