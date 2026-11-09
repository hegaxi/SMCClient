/* Reglas de seguridad en SQL Server: usuarios, contraseñas, bloqueo, roles, permisos y auditoría.
   Los hash son bytes ficticios: SQL no verifica contraseñas (lo hace la API con PBKDF2); aquí se prueban las reglas.
   Ejecutar sobre una base recién desplegada:  sqlcmd -b -I -x -d SMCClient -i tests/020_prueba_seguridad.sql */
SET NOCOUNT ON;
GO
IF SCHEMA_ID('prueba') IS NULL EXEC ('CREATE SCHEMA prueba');
GO
CREATE OR ALTER PROCEDURE prueba.Afirmar @Condicion bit, @Mensaje nvarchar(400)
AS
BEGIN
    IF ISNULL(@Condicion, 0) = 0 BEGIN DECLARE @m nvarchar(500) = N'FALLÓ: ' + @Mensaje; THROW 50999, @m, 1; END;
    PRINT N'ok  ' + @Mensaje;
END;
GO
/* Ejecuta @Sql y verifica que falle con el error @Numero. */
CREATE OR ALTER PROCEDURE prueba.AfirmarError @Sql nvarchar(max), @Numero int, @Mensaje nvarchar(400)
AS
BEGIN
    DECLARE @n int = 0, @texto nvarchar(4000);
    BEGIN TRY
        EXEC sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        SELECT @n = ERROR_NUMBER(), @texto = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0 ROLLBACK;
    END CATCH;
    DECLARE @ok bit = CASE WHEN @n = @Numero THEN 1 ELSE 0 END;
    DECLARE @m nvarchar(800) = CONCAT(@Mensaje, CASE WHEN @ok = 0 THEN CONCAT(N' (error ', @n, N': ', @texto, N')') ELSE N'' END);
    EXEC prueba.Afirmar @ok, @m;
END;
GO
/* Lista de procedimientos permitidos como texto, para verificarlos fácilmente. */
CREATE OR ALTER PROCEDURE prueba.Permisos @Login nvarchar(100), @Sello uniqueidentifier = NULL,
    @Lista nvarchar(max) OUTPUT, @Valido bit OUTPUT, @DebeCambiar bit OUTPUT
AS
BEGIN
    DECLARE @p TABLE (Procedimiento sysname);
    INSERT @p EXEC seg.Permisos_Usuario @Login = @Login, @Sello = @Sello, @Valido = @Valido OUTPUT, @DebeCambiar = @DebeCambiar OUTPUT;
    SET @Lista = N',' + ISNULL((SELECT STRING_AGG(Procedimiento, N',') FROM @p), N'') + N',';
END;
GO

DECLARE @ok bit, @lista nvarchar(max), @valido bit, @cambiar bit, @sello uniqueidentifier, @r varchar(12);
DECLARE @h varbinary(64) = 0x0102, @s varbinary(32) = 0x0A0B;
DECLARE @res TABLE (Resultado varchar(12), Nombre nvarchar(200), Sello uniqueidentifier, DebeCambiar bit);
DECLARE @ignorar TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
DECLARE @ignorarRoles TABLE (a nvarchar(100), b nvarchar(400), c nvarchar(2000), d int, e bit);

/* ===== Roles de sistema ===== */
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM seg.Rol WHERE EsSistema = 1); EXEC prueba.Afirmar @ok, N'Roles de sistema: Administrador y Consulta';
SET @ok = (SELECT CASE WHEN STRING_AGG(rp.Permiso, ',') WITHIN GROUP (ORDER BY rp.Permiso) = 'admin,lectura,usuario' THEN 1 ELSE 0 END FROM seg.RolPermiso rp JOIN seg.Rol r ON r.RolId = rp.RolId WHERE r.Nombre = N'Administrador');
EXEC prueba.Afirmar @ok, N'Administrador tiene admin, lectura y usuario';

/* ===== Primer administrador (comando de instalación) ===== */
EXEC prueba.AfirmarError N'EXEC seg.Instalacion_CrearAdministrador @Login = N''admin1'', @Nombre = N''A'', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 5;', 50400, N'Contraseña corta rechazada al instalar';
EXEC seg.Instalacion_CrearAdministrador @Login = N'admin1', @Nombre = N'Admin Uno', @Hash = @h, @Sal = @s, @Iteraciones = 600000, @Longitud = 12;
EXEC prueba.Permisos @Login = N'admin1', @Lista = @lista OUTPUT, @Valido = @valido OUTPUT, @DebeCambiar = @cambiar OUTPUT;
SET @ok = CASE WHEN @valido = 1 AND @cambiar = 0 AND @lista LIKE N'%,Usuarios_Listar,%' AND @lista LIKE N'%,Issues_Buscar,%' AND @lista LIKE N'%,Mi_Usuario,%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El administrador puede consultar y administrar';

/* ===== Alta de un usuario sin contraseña ===== */
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'lector', @Nombre = N'Lector', @Roles = N'Consulta', @UsuarioActual = N'admin1';
EXEC prueba.Permisos @Login = N'lector', @Lista = @lista OUTPUT, @Valido = @valido OUTPUT, @DebeCambiar = @cambiar OUTPUT;
SET @ok = CASE WHEN @valido = 1 AND @cambiar = 1 AND @lista = N',,' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Usuario nuevo: debe establecer su contraseña y aún no puede consultar';
EXEC prueba.AfirmarError N'DECLARE @t TABLE (a varbinary(64), b varbinary(32), c int); INSERT @t EXEC seg.Login_Credencial @Login = N''lector''; IF NOT EXISTS (SELECT 1 FROM @t) THROW 50001, ''sin credencial'', 1;', 50001, N'Usuario sin contraseña: no hay credencial que verificar';
EXEC prueba.AfirmarError N'EXEC api.Usuario_Guardar @Login = N''con espacio'', @Roles = N''Consulta'', @UsuarioActual = N''admin1'';', 50400, N'Nombre de usuario con espacios rechazado';
EXEC prueba.AfirmarError N'EXEC api.Usuario_Guardar @Login = N''x'', @Roles = N''NoExiste'', @UsuarioActual = N''admin1'';', 50400, N'Rol inexistente rechazado';

/* ===== Contraseñas ===== */
EXEC prueba.AfirmarError N'EXEC seg.Contrasena_Establecer @Login = N''lector'', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12, @UsuarioActual = N''lector'';', 50400, N'Cambiar la propia sin verificar la actual: rechazado';
EXEC prueba.AfirmarError N'EXEC seg.Contrasena_Establecer @Login = N''lector'', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 4, @UsuarioActual = N''admin1'';', 50400, N'Longitud mínima aplicada por la base';
EXEC seg.Contrasena_Establecer @Login = N'lector', @Hash = @h, @Sal = @s, @Iteraciones = 600000, @Longitud = 12, @UsuarioActual = N'admin1', @SelloNuevo = @sello OUTPUT;
SET @ok = (SELECT CASE WHEN DebeCambiarContrasena = 1 AND SelloSeguridad = @sello THEN 1 ELSE 0 END FROM seg.Usuario WHERE Login = N'lector');
EXEC prueba.Afirmar @ok, N'El administrador restablece: el usuario debe cambiarla al entrar';
DECLARE @selloViejo uniqueidentifier = @sello;
EXEC seg.Contrasena_Establecer @Login = N'lector', @Hash = @h, @Sal = @s, @Iteraciones = 600000, @Longitud = 14, @UsuarioActual = N'lector', @ActualVerificada = 1, @SelloNuevo = @sello OUTPUT;
EXEC prueba.Permisos @Login = N'lector', @Sello = @sello, @Lista = @lista OUTPUT, @Valido = @valido OUTPUT, @DebeCambiar = @cambiar OUTPUT;
SET @ok = CASE WHEN @valido = 1 AND @cambiar = 0 AND @lista LIKE N'%,Issues_Buscar,%' AND @lista NOT LIKE N'%,Usuarios_Listar,%' AND @lista LIKE N'%,Mi_Usuario,%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Consulta: consulta pero no administra';
EXEC prueba.Permisos @Login = N'lector', @Sello = @selloViejo, @Lista = @lista OUTPUT, @Valido = @valido OUTPUT, @DebeCambiar = @cambiar OUTPUT;
SET @ok = CASE WHEN @valido = 0 THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Sesión con sello anterior (otra contraseña): inválida';
EXEC prueba.AfirmarError N'EXEC seg.Contrasena_Establecer @Login = N''admin1'', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12, @UsuarioActual = N''lector'';', 50403, N'Un usuario sin administración no puede restablecer contraseñas de otros';
GO

/* ===== Inicio de sesión y bloqueo ===== */
DECLARE @ok bit, @i int = 1;
DECLARE @res TABLE (Resultado varchar(12), Nombre nvarchar(200), Sello uniqueidentifier, DebeCambiar bit);
WHILE @i <= 4
BEGIN
    INSERT @res EXEC seg.Login_Resultado @Login = N'lector', @Coincide = 0, @Origen = N'10.0.0.1';
    SET @i += 1;
END;
SET @ok = (SELECT CASE WHEN COUNT(*) = 4 AND MIN(Resultado) = 'invalido' AND MAX(Resultado) = 'invalido' THEN 1 ELSE 0 END FROM @res);
EXEC prueba.Afirmar @ok, N'4 intentos fallidos: contraseña incorrecta';
DELETE @res; INSERT @res EXEC seg.Login_Resultado @Login = N'lector', @Coincide = 0;
SET @ok = (SELECT CASE WHEN Resultado = 'bloqueado' THEN 1 ELSE 0 END FROM @res); EXEC prueba.Afirmar @ok, N'5º intento fallido: cuenta bloqueada';
DELETE @res; INSERT @res EXEC seg.Login_Resultado @Login = N'lector', @Coincide = 1;
SET @ok = (SELECT CASE WHEN Resultado = 'bloqueado' AND Sello IS NULL THEN 1 ELSE 0 END FROM @res); EXEC prueba.Afirmar @ok, N'Bloqueada: ni con la contraseña correcta entra';
UPDATE seg.Usuario SET BloqueadoHasta = DATEADD(MINUTE, -1, SYSDATETIMEOFFSET()) WHERE Login = N'lector';   -- pasa el tiempo de bloqueo
DELETE @res; INSERT @res EXEC seg.Login_Resultado @Login = N'lector', @Coincide = 1;
SET @ok = (SELECT CASE WHEN Resultado = 'ok' AND Sello IS NOT NULL AND Nombre = N'Lector' AND DebeCambiar = 0 THEN 1 ELSE 0 END FROM @res); EXEC prueba.Afirmar @ok, N'Pasado el bloqueo entra y recibe el sello de su sesión';
SET @ok = (SELECT CASE WHEN IntentosFallidos = 0 AND UltimoAcceso IS NOT NULL THEN 1 ELSE 0 END FROM seg.Usuario WHERE Login = N'lector'); EXEC prueba.Afirmar @ok, N'Al entrar se reinician los intentos';
DELETE @res; INSERT @res EXEC seg.Login_Resultado @Login = N'nadie', @Coincide = 0;
SET @ok = (SELECT CASE WHEN Resultado = 'invalido' THEN 1 ELSE 0 END FROM @res); EXEC prueba.Afirmar @ok, N'Usuario inexistente: mismo resultado que contraseña incorrecta';
GO

/* ===== Reglas de administración ===== */
DECLARE @ok bit, @lista nvarchar(max), @valido bit, @cambiar bit;
DECLARE @ignorar TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
DECLARE @ignorarRoles TABLE (a nvarchar(100), b nvarchar(400), c nvarchar(2000), d int, e bit);
DECLARE @res TABLE (Resultado varchar(12), Nombre nvarchar(200), Sello uniqueidentifier, DebeCambiar bit);

EXEC prueba.AfirmarError N'EXEC api.Usuario_Guardar @Login = N''admin1'', @Roles = N''Consulta'', @UsuarioActual = N''admin1'';', 50409, N'Nadie se quita a sí mismo la administración';
EXEC prueba.AfirmarError N'EXEC api.Usuario_Guardar @Login = N''admin1'', @Activo = 0, @Roles = N''Administrador'', @UsuarioActual = N''admin1'';', 50409, N'Nadie se desactiva a sí mismo';
EXEC prueba.AfirmarError N'EXEC api.Rol_Guardar @Nombre = N''Administrador'', @Permisos = N''lectura'', @UsuarioActual = N''admin1'';', 50409, N'El rol Administrador conserva el permiso admin';
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'admin2', @Nombre = N'Admin Dos', @Roles = N'Administrador', @UsuarioActual = N'admin1';
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'admin1', @Roles = N'Consulta', @UsuarioActual = N'admin2';
SET @ok = (SELECT CASE WHEN seg.fn_AdministradoresActivos() = 1 THEN 1 ELSE 0 END); EXEC prueba.Afirmar @ok, N'Otro administrador sí puede quitarle la administración';
EXEC prueba.AfirmarError N'EXEC api.Usuario_Guardar @Login = N''admin2'', @Roles = N''Consulta'', @UsuarioActual = N''admin1'';', 50409, N'Siempre queda al menos un administrador activo';

-- Permiso fino: un rol que solo ve los SLA por vencer.
EXEC prueba.AfirmarError N'EXEC api.Rol_Guardar @Nombre = N''Soporte'', @Permisos = N''api.NoExiste'', @UsuarioActual = N''admin2'';', 50400, N'Permiso a un procedimiento inexistente rechazado';
INSERT @ignorarRoles EXEC api.Rol_Guardar @Nombre = N'Soporte', @Descripcion = N'Mesa de ayuda', @Permisos = N'api.Sla_EnRiesgo', @UsuarioActual = N'admin2';
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'soporte1', @Nombre = N'Soporte Uno', @Roles = N'Soporte', @UsuarioActual = N'admin2';
UPDATE seg.Usuario SET DebeCambiarContrasena = 0 WHERE Login = N'soporte1';
EXEC prueba.Permisos @Login = N'soporte1', @Lista = @lista OUTPUT, @Valido = @valido OUTPUT, @DebeCambiar = @cambiar OUTPUT;
SET @ok = CASE WHEN @lista LIKE N'%,Sla_EnRiesgo,%' AND @lista NOT LIKE N'%,Issues_Buscar,%' AND @lista LIKE N'%,Mi_Usuario,%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Rol con permiso a un solo procedimiento';
-- Editar sin indicar permisos, roles ni estado los conserva (antes se borraban los permisos y se reactivaba al usuario).
INSERT @ignorarRoles EXEC api.Rol_Guardar @Nombre = N'Soporte', @Descripcion = N'Mesa de ayuda N1', @UsuarioActual = N'admin2';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 AND MIN(rp.Permiso) = N'api.Sla_EnRiesgo' THEN 1 ELSE 0 END
           FROM seg.RolPermiso rp JOIN seg.Rol r ON r.RolId = rp.RolId WHERE r.Nombre = N'Soporte');
EXEC prueba.Afirmar @ok, N'Editar un rol sin @Permisos conserva sus permisos';
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'soporte1', @Nombre = N'Soporte 1', @UsuarioActual = N'admin2';
SET @ok = (SELECT CASE WHEN u.Nombre = N'Soporte 1' AND u.Activo = 1 AND r.Nombre = N'Soporte' THEN 1 ELSE 0 END
           FROM seg.Usuario u JOIN seg.UsuarioRol ur ON ur.UsuarioId = u.UsuarioId JOIN seg.Rol r ON r.RolId = ur.RolId WHERE u.Login = N'soporte1');
EXEC prueba.Afirmar @ok, N'Editar un usuario sin @Roles ni @Activo los conserva';
EXEC prueba.AfirmarError N'EXEC api.Usuario_Guardar @Login = N''nuevo_sin_rol'', @UsuarioActual = N''admin2'';', 50400, N'Un usuario nuevo necesita al menos un rol';
EXEC prueba.AfirmarError N'EXEC api.Rol_Eliminar @Nombre = N''Soporte'', @UsuarioActual = N''admin2'';', 50409, N'No se elimina un rol con usuarios';
EXEC prueba.AfirmarError N'EXEC api.Rol_Eliminar @Nombre = N''Consulta'', @UsuarioActual = N''admin2'';', 50409, N'No se elimina un rol del sistema';
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'soporte1', @Activo = 0, @Roles = N'', @UsuarioActual = N'admin2';
INSERT @ignorar EXEC api.Usuario_Guardar @Login = N'soporte1', @Nombre = N'Soporte Uno', @UsuarioActual = N'admin2';
SET @ok = (SELECT CASE WHEN Activo = 0 THEN 1 ELSE 0 END FROM seg.Usuario WHERE Login = N'soporte1');
EXEC prueba.Afirmar @ok, N'Editar a un usuario inactivo sin @Activo no lo reactiva';
INSERT @ignorarRoles EXEC api.Rol_Eliminar @Nombre = N'Soporte', @UsuarioActual = N'admin2';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM seg.Rol WHERE Nombre = N'Soporte'); EXEC prueba.Afirmar @ok, N'Rol sin usuarios eliminado';
DELETE @res; INSERT @res EXEC seg.Login_Resultado @Login = N'soporte1', @Coincide = 1;
SET @ok = (SELECT CASE WHEN Resultado = 'inactivo' THEN 1 ELSE 0 END FROM @res); EXEC prueba.Afirmar @ok, N'Usuario desactivado no entra';

/* ===== Auditoría ===== */
SET @ok = (SELECT CASE WHEN COUNT(DISTINCT Accion) = 9 THEN 1 ELSE 0 END FROM seg.Auditoria
           WHERE Accion IN ('usuario.administrador_instalacion', 'usuario.guardar', 'contrasena.restablecer', 'contrasena.cambiar',
                            'sesion.fallida', 'sesion.bloqueo', 'sesion.inicio', 'rol.guardar', 'rol.eliminar'));
EXEC prueba.Afirmar @ok, N'Todo queda en la auditoría (instalación, usuarios, contraseñas, sesiones, roles)';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM seg.Auditoria WHERE Antes LIKE '%0x01%' OR Despues LIKE '%Hash%'); EXEC prueba.Afirmar @ok, N'La auditoría no guarda datos de contraseñas';
GO

DROP PROCEDURE prueba.Permisos; DROP PROCEDURE prueba.AfirmarError; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DE SEGURIDAD PASARON';
GO
