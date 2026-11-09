/* 1 si el usuario tiene algún rol externo (cliente). */
CREATE OR ALTER FUNCTION seg.fn_EsExterno (@UsuarioId int)
RETURNS bit
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId
                             WHERE ur.UsuarioId = @UsuarioId AND r.EsExterno = 1) THEN 1 ELSE 0 END;
END;
GO
