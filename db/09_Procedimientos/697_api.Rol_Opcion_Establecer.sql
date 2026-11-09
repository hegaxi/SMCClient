/* Concede o quita UNA opción del menú (o una categoría completa) a un rol: la casilla de "Permisos por opción".
   Aplica las mismas reglas que api.Rol_Guardar (permisos válidos, roles externos, el rol Administrador conserva admin,
   siempre queda un administrador activo) y queda en la auditoría. */
CREATE OR ALTER PROCEDURE api.Rol_Opcion_Establecer
    @Rol           nvarchar(100),
    @Permiso       nvarchar(200),
    @Concedido     bit,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @Permiso = LTRIM(RTRIM(@Permiso));
    IF NOT EXISTS (SELECT 1 FROM seg.Rol WHERE Nombre = @Rol) THROW 50404, 'El rol no existe.', 1;
    IF @Permiso = N'' OR @Permiso LIKE N'%,%' THROW 50400, 'Indique un solo permiso.', 1;

    DECLARE @lista nvarchar(max) = (
        SELECT STRING_AGG(CAST(x.Permiso AS nvarchar(max)), N',')
        FROM (SELECT rp.Permiso FROM seg.RolPermiso rp JOIN seg.Rol r ON r.RolId = rp.RolId
              WHERE r.Nombre = @Rol AND rp.Permiso <> @Permiso
              UNION ALL
              SELECT @Permiso WHERE @Concedido = 1) x);

    -- Devuelve la lista de roles con sus permisos (la de api.Rol_Guardar).
    EXEC api.Rol_Guardar @Nombre = @Rol, @Permisos = @lista, @UsuarioActual = @UsuarioActual;
END;
GO
