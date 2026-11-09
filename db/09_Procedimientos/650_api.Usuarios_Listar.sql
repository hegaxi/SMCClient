CREATE OR ALTER PROCEDURE api.Usuarios_Listar
    @Texto       nvarchar(100) = NULL,
    @SoloActivos bit = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.Login, u.Nombre, u.Activo,
           (SELECT STRING_AGG(r.Nombre, N', ') WITHIN GROUP (ORDER BY r.Nombre)
            FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId WHERE ur.UsuarioId = u.UsuarioId) AS Roles,
           u.UltimoAcceso, u.FechaAlta
    FROM seg.Usuario u
    WHERE (@Texto IS NULL OR u.Login LIKE N'%' + @Texto + N'%' OR u.Nombre LIKE N'%' + @Texto + N'%')
      AND (@SoloActivos IS NULL OR u.Activo = @SoloActivos)
    ORDER BY u.Activo DESC, u.Nombre;
END;
GO
