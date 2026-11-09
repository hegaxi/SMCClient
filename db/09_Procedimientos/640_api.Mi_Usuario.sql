/* Quién soy y qué roles tengo (para el encabezado de la aplicación). */
CREATE OR ALTER PROCEDURE api.Mi_Usuario
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.Login, u.Nombre,
           (SELECT STRING_AGG(r.Nombre, N', ') WITHIN GROUP (ORDER BY r.Nombre)
            FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId WHERE ur.UsuarioId = u.UsuarioId) AS Roles,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                                  WHERE ur.UsuarioId = u.UsuarioId AND rp.Permiso = N'admin') THEN 1 ELSE 0 END AS bit) AS EsAdministrador,
           seg.fn_TieneOpcion(u.UsuarioId, N'contrasena.restablecer') AS PuedeRestablecerContrasena
    FROM seg.Usuario u
    WHERE u.Login = @UsuarioActual;
END;
GO
