/* Elimina un rol que no es de sistema y no tiene usuarios asignados. */
CREATE OR ALTER PROCEDURE api.Rol_Eliminar
    @Nombre        nvarchar(100),
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @RolId int, @sistema bit;
    SELECT @RolId = RolId, @sistema = EsSistema FROM seg.Rol WHERE Nombre = @Nombre;
    IF @RolId IS NULL THROW 50404, 'El rol no existe.', 1;
    IF @sistema = 1 THROW 50409, 'Los roles del sistema no se pueden eliminar.', 1;
    IF EXISTS (SELECT 1 FROM seg.UsuarioRol WHERE RolId = @RolId) THROW 50409, 'El rol tiene usuarios asignados; quíteselo primero.', 1;

    DECLARE @antes nvarchar(max) = (SELECT r.Descripcion, (SELECT STRING_AGG(rp.Permiso, N',') FROM seg.RolPermiso rp WHERE rp.RolId = r.RolId) AS Permisos
                                    FROM seg.Rol r WHERE r.RolId = @RolId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRAN;
    DELETE seg.Rol WHERE RolId = @RolId;
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'rol.eliminar', @Objeto = @Nombre, @Antes = @antes;
    COMMIT;

    EXEC api.Roles_Listar;
END;
GO
