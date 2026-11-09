/* Procedimientos del esquema api que puede ejecutar un usuario activo (sin revisar sello ni cambio de contraseña):
   smc:permiso = usuario -> todos; lectura / admin (sin propiedad = admin) -> según sus roles (categoría o api.Nombre).
   Un usuario con un rol EXTERNO (cliente) solo ejecuta los "usuario" (consultas personalizadas compartidas con él, sus
   tableros y su contraseña), aunque alguno de sus roles tenga más permisos: así un error de configuración no le abre
   los reportes internos.
   La usan seg.Permisos_Usuario y las reglas de filtros y tableros. */
CREATE OR ALTER FUNCTION seg.fn_ProcedimientosPermitidos (@UsuarioId int)
RETURNS TABLE
AS
RETURN
    SELECT p.name AS Procedimiento
    FROM sys.procedures p
    CROSS APPLY (SELECT ISNULL(CAST((SELECT value FROM sys.extended_properties
                                     WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:permiso') AS nvarchar(50)), N'admin') AS Permiso) x
    WHERE p.schema_id = SCHEMA_ID('api')
      AND EXISTS (SELECT 1 FROM seg.Usuario u WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1)
      AND (x.Permiso = N'usuario'
           OR (EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                       WHERE ur.UsuarioId = @UsuarioId AND (rp.Permiso = x.Permiso OR rp.Permiso = N'api.' + p.name))
               AND NOT EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId
                               WHERE ur.UsuarioId = @UsuarioId AND r.EsExterno = 1)));
GO
