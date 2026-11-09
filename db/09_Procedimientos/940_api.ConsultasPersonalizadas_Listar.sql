/* Consultas personalizadas que puede ver el usuario (los administradores ven todas, con quién están compartidas). */
CREATE OR ALTER PROCEDURE api.ConsultasPersonalizadas_Listar
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    DECLARE @admin bit = CASE WHEN EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@u) WHERE Procedimiento = N'ConsultaPersonalizada_Guardar') THEN 1 ELSE 0 END;   -- las administra
    SELECT c.ConsultaId, c.Nombre, c.Descripcion,
           CASE WHEN @admin = 1 THEN a.CompartidaCon END AS CompartidaCon,
           c.FechaCambio, @admin AS PuedoEditar
    FROM dash.Consulta c
    OUTER APPLY (
        SELECT STRING_AGG(CASE x.Tipo WHEN 'U' THEN us.Login ELSE N'rol:' + r.Nombre END, N', ') AS CompartidaCon
        FROM dash.ConsultaAcceso x
        LEFT JOIN seg.Usuario us ON x.Tipo = 'U' AND us.UsuarioId = x.Id
        LEFT JOIN seg.Rol r ON x.Tipo = 'R' AND r.RolId = x.Id
        WHERE x.ConsultaId = c.ConsultaId
    ) a
    WHERE @u IS NOT NULL
      AND (@admin = 1 OR EXISTS (SELECT 1 FROM dash.ConsultaAcceso x
                                 WHERE x.ConsultaId = c.ConsultaId
                                   AND ((x.Tipo = 'U' AND x.Id = @u)
                                        OR (x.Tipo = 'R' AND x.Id IN (SELECT RolId FROM seg.UsuarioRol WHERE UsuarioId = @u)))))
    ORDER BY c.Nombre;
END;
GO
