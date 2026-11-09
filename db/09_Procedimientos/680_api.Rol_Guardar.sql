/* Alta o cambio de un rol y sus permisos (reemplaza los permisos). @Permisos, separados por coma:
   lectura | admin | api.Nombre (un procedimiento específico). Reglas:
   - Cada permiso debe ser una categoría válida o un procedimiento existente del esquema api.
   - El rol Administrador siempre conserva 'admin'.
   - Siempre debe quedar al menos un administrador activo. */
CREATE OR ALTER PROCEDURE api.Rol_Guardar
    @Nombre        nvarchar(100),
    @Descripcion   nvarchar(400) = NULL,
    @Permisos      nvarchar(2000) = N'',
    @EsExterno     bit = NULL,       -- 1 = rol de clientes: solo consultas personalizadas, limitadas a su organización
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF @Nombre = N'' THROW 50400, 'El nombre del rol es obligatorio.', 1;

    DECLARE @p TABLE (Permiso nvarchar(200) PRIMARY KEY);
    INSERT @p SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(@Permisos, N''), ',') WHERE LTRIM(RTRIM(value)) <> N'';
    IF @EsExterno = 1 AND EXISTS (SELECT 1 FROM @p WHERE Permiso = N'admin') THROW 50400, 'Un rol externo (clientes) no puede tener el permiso admin.', 1;

    DECLARE @msg nvarchar(1000) = (SELECT STRING_AGG(x.Permiso, N', ') FROM @p x
                                   WHERE x.Permiso NOT IN (N'lectura', N'admin')
                                     AND NOT (x.Permiso LIKE N'api.%' AND OBJECT_ID(x.Permiso, 'P') IS NOT NULL AND OBJECT_SCHEMA_NAME(OBJECT_ID(x.Permiso)) = N'api'));
    IF @msg IS NOT NULL
    BEGIN
        SET @msg = N'Permisos inválidos: ' + @msg + N'. Use lectura, admin o api.NombreDelProcedimiento.';
        THROW 50400, @msg, 1;
    END;
    IF EXISTS (SELECT 1 FROM seg.Rol WHERE Nombre = @Nombre AND EsSistema = 1 AND Nombre = N'Administrador')
       AND NOT EXISTS (SELECT 1 FROM @p WHERE Permiso = N'admin')
        THROW 50409, 'El rol Administrador debe conservar el permiso admin.', 1;

    DECLARE @antes nvarchar(max) = (SELECT r.Descripcion, (SELECT STRING_AGG(rp.Permiso, N',') FROM seg.RolPermiso rp WHERE rp.RolId = r.RolId) AS Permisos
                                    FROM seg.Rol r WHERE r.Nombre = @Nombre FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRAN;
    IF EXISTS (SELECT 1 FROM seg.Rol WHERE Nombre = @Nombre)
        UPDATE seg.Rol SET Descripcion = COALESCE(@Descripcion, Descripcion), EsExterno = COALESCE(@EsExterno, EsExterno) WHERE Nombre = @Nombre;
    ELSE
        INSERT seg.Rol (Nombre, Descripcion, EsExterno) VALUES (@Nombre, @Descripcion, ISNULL(@EsExterno, 0));

    DECLARE @RolId int = (SELECT RolId FROM seg.Rol WHERE Nombre = @Nombre);
    DELETE seg.RolPermiso WHERE RolId = @RolId;
    INSERT seg.RolPermiso (RolId, Permiso) SELECT @RolId, Permiso FROM @p;

    IF seg.fn_AdministradoresActivos() = 0
    BEGIN
        ROLLBACK;
        THROW 50409, 'Debe quedar al menos un administrador activo.', 1;
    END;

    DECLARE @despues nvarchar(max) = (SELECT @Descripcion AS Descripcion, @Permisos AS Permisos FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'rol.guardar', @Objeto = @Nombre, @Antes = @antes, @Despues = @despues;
    COMMIT;

    EXEC api.Roles_Listar;
END;
GO
