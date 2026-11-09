/* Alta o cambio de un rol y sus permisos. Sin @Permisos (NULL) se conservan los que tiene; con valor los reemplaza
   (N'' los quita todos). @Permisos, separados por coma:
   una categoría completa (lectura | admin | usuario), una opción de menú (su código en seg.fn_Opciones, p. ej. tableros,
   contrasena.restablecer, api.Horas_PorPersona) o api.Nombre (un procedimiento). Reglas:
   - Cada permiso debe ser una categoría, una opción o un procedimiento existente del esquema api.
   - Un rol externo (clientes) solo puede tener la categoría usuario u opciones de esa categoría.
   - El rol Administrador siempre conserva 'admin'.
   - Siempre debe quedar al menos un administrador activo. */
CREATE OR ALTER PROCEDURE api.Rol_Guardar
    @Nombre        nvarchar(100),
    @Descripcion   nvarchar(400) = NULL,
    @Permisos      nvarchar(max) = NULL,   -- NULL = conservar los actuales
    @EsExterno     bit = NULL,       -- 1 = rol de clientes: solo consultas personalizadas, limitadas a su organización
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF @Nombre = N'' THROW 50400, 'El nombre del rol es obligatorio.', 1;

    DECLARE @p TABLE (Permiso nvarchar(200) PRIMARY KEY);
    IF @Permisos IS NULL
        INSERT @p SELECT rp.Permiso FROM seg.RolPermiso rp JOIN seg.Rol r ON r.RolId = rp.RolId WHERE r.Nombre = @Nombre;
    ELSE
        INSERT @p SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Permisos, ',') WHERE LTRIM(RTRIM(value)) <> N'';
    -- Categoría de cada permiso: la propia (lectura/admin/usuario), la de su opción o la de su procedimiento.
    DECLARE @cat TABLE (Permiso nvarchar(200) PRIMARY KEY, Categoria nvarchar(200) NULL);
    INSERT @cat
    SELECT x.Permiso,
           CASE WHEN x.Permiso IN (N'lectura', N'admin', N'usuario') THEN x.Permiso
                ELSE COALESCE((SELECT o.Categoria FROM seg.fn_Opciones() o WHERE o.Codigo = x.Permiso),
                              (SELECT o.Categoria FROM seg.fn_OpcionProcedimiento() o WHERE N'api.' + o.Procedimiento = x.Permiso AND o.Categoria <> N'sesion')) END
    FROM @p x;

    DECLARE @msg nvarchar(max) = (SELECT STRING_AGG(Permiso, N', ') FROM @cat WHERE Categoria IS NULL);
    IF @msg IS NOT NULL
    BEGIN
        SET @msg = N'Permisos inválidos: ' + @msg + N'. Use lectura, admin, usuario, el código de una opción o api.NombreDelProcedimiento.';
        THROW 50400, @msg, 1;
    END;
    IF COALESCE(@EsExterno, (SELECT EsExterno FROM seg.Rol WHERE Nombre = @Nombre), 0) = 1
    BEGIN
        SET @msg = (SELECT STRING_AGG(Permiso, N', ') FROM @cat WHERE Categoria <> N'usuario');
        IF @msg IS NOT NULL
        BEGIN
            SET @msg = N'Un rol externo (clientes) solo puede tener tableros, filtros y consultas personalizadas. No permitido: ' + @msg + N'.';
            THROW 50400, @msg, 1;
        END;
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

    DECLARE @despues nvarchar(max) = (SELECT @Descripcion AS Descripcion, (SELECT STRING_AGG(Permiso, N',') FROM @p) AS Permisos FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'rol.guardar', @Objeto = @Nombre, @Antes = @antes, @Despues = @despues;
    COMMIT;

    EXEC api.Roles_Listar;
END;
GO
