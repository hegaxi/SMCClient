/* LA decisión de autorización. La API la llama en cada petición (con caché de segundos) con el usuario y el
   sello de su sesión, y solo deja ejecutar los procedimientos que devuelve. Reglas:
   - Usuario inexistente, inactivo o con sello distinto (cambió su contraseña o lo desactivaron): @Valido = 0,
     la API cierra la sesión.
   - Debe cambiar su contraseña: @DebeCambiar = 1 y ningún procedimiento.
   - smc:permiso = usuario   -> cualquier usuario activo.
   - smc:permiso = lectura / admin (sin propiedad = admin) -> si alguno de sus roles tiene esa categoría
     o el procedimiento específico ('api.Nombre') en seg.RolPermiso. */
CREATE OR ALTER PROCEDURE seg.Permisos_Usuario
    @Login       nvarchar(100),
    @Sello       uniqueidentifier = NULL,
    @Valido      bit = NULL OUTPUT,
    @DebeCambiar bit = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int;
    SELECT @UsuarioId = UsuarioId, @DebeCambiar = DebeCambiarContrasena
    FROM seg.Usuario
    WHERE Login = @Login AND Activo = 1 AND (@Sello IS NULL OR SelloSeguridad = @Sello);

    SET @Valido = CASE WHEN @UsuarioId IS NULL THEN 0 ELSE 1 END;
    IF @UsuarioId IS NULL OR @DebeCambiar = 1
    BEGIN
        SELECT CAST(NULL AS sysname) AS Procedimiento WHERE 1 = 0;
        RETURN;
    END;

    SELECT p.name AS Procedimiento
    FROM sys.procedures p
    CROSS APPLY (SELECT ISNULL(CAST((SELECT value FROM sys.extended_properties
                                     WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:permiso') AS nvarchar(50)), N'admin') AS Permiso) x
    WHERE p.schema_id = SCHEMA_ID('api')
      AND (x.Permiso = N'usuario'
           OR EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                      WHERE ur.UsuarioId = @UsuarioId AND (rp.Permiso = x.Permiso OR rp.Permiso = N'api.' + p.name)))
    ORDER BY p.name;
END;
GO
