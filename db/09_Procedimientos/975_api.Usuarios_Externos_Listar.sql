/* Usuarios externos (con un rol externo, p. ej. Cliente): sus organizaciones y las consultas personalizadas que ven. */
CREATE OR ALTER PROCEDURE api.Usuarios_Externos_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.Login, u.Nombre, u.Activo,
           (SELECT STRING_AGG(r.Nombre, N', ') FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId WHERE ur.UsuarioId = u.UsuarioId) AS Roles,
           ISNULL((SELECT STRING_AGG(o.Organizacion, N' | ') FROM seg.UsuarioOrganizacion o WHERE o.UsuarioId = u.UsuarioId), N'(sin organización: no ve tickets)') AS Organizaciones,
           (SELECT STRING_AGG(c.Nombre, N', ') FROM dash.Consulta c
            WHERE EXISTS (SELECT 1 FROM dash.ConsultaAcceso x WHERE x.ConsultaId = c.ConsultaId
                            AND ((x.Tipo = 'U' AND x.Id = u.UsuarioId) OR (x.Tipo = 'R' AND x.Id IN (SELECT RolId FROM seg.UsuarioRol WHERE UsuarioId = u.UsuarioId))))) AS Consultas
    FROM seg.Usuario u
    WHERE seg.fn_EsExterno(u.UsuarioId) = 1
    ORDER BY u.Login;
END;
GO
