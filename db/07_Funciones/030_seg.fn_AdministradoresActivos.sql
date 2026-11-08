/* Usuarios activos con un rol que tiene la categoría 'admin'. Regla: nunca puede quedar en cero. */
CREATE OR ALTER FUNCTION seg.fn_AdministradoresActivos ()
RETURNS int
AS
BEGIN
    RETURN (SELECT COUNT(DISTINCT u.UsuarioId)
            FROM seg.Usuario u
            JOIN seg.UsuarioRol ur ON ur.UsuarioId = u.UsuarioId
            JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
            WHERE u.Activo = 1 AND rp.Permiso = N'admin');
END;
GO
