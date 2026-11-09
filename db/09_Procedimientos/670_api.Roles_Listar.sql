CREATE OR ALTER PROCEDURE api.Roles_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.Nombre, r.Descripcion,
           (SELECT STRING_AGG(rp.Permiso, N', ') WITHIN GROUP (ORDER BY rp.Permiso) FROM seg.RolPermiso rp WHERE rp.RolId = r.RolId) AS Permisos,
           (SELECT COUNT(*) FROM seg.UsuarioRol ur JOIN seg.Usuario u ON u.UsuarioId = ur.UsuarioId WHERE ur.RolId = r.RolId AND u.Activo = 1) AS UsuariosActivos,
           r.EsSistema
    FROM seg.Rol r
    ORDER BY r.EsSistema DESC, r.Nombre;
END;
GO
