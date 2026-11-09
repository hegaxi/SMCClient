/* 1 si el usuario activo tiene concedida la opción (por su código o por su categoría completa). Para las opciones que no
   son procedimientos (p. ej. 'contrasena.restablecer'); las demás se revisan con seg.fn_ProcedimientosPermitidos.
   Un usuario externo solo puede tener opciones de la categoría 'usuario'. */
CREATE OR ALTER FUNCTION seg.fn_TieneOpcion (@UsuarioId int, @Opcion nvarchar(200))
RETURNS bit
AS
BEGIN
    DECLARE @categoria nvarchar(200) = (SELECT Categoria FROM seg.fn_Opciones() WHERE Codigo = @Opcion);
    IF @categoria IS NULL RETURN 0;
    IF @categoria <> N'usuario' AND EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId
                                            WHERE ur.UsuarioId = @UsuarioId AND r.EsExterno = 1) RETURN 0;
    RETURN CASE WHEN EXISTS (SELECT 1 FROM seg.Usuario u JOIN seg.UsuarioRol ur ON ur.UsuarioId = u.UsuarioId
                             JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                             WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1 AND rp.Permiso IN (@Opcion, @categoria)) THEN 1 ELSE 0 END;
END;
GO
