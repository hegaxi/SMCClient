CREATE OR ALTER FUNCTION seg.fn_EsAdministrador (@UsuarioId int)
RETURNS bit
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM seg.Usuario u JOIN seg.UsuarioRol ur ON ur.UsuarioId = u.UsuarioId
                             JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                             WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1 AND rp.Permiso = N'admin') THEN 1 ELSE 0 END;
END;
GO
