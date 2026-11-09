/* Filtros que puede usar el usuario: los suyos y los compartidos de consultas que tiene permitidas. */
CREATE OR ALTER PROCEDURE api.Filtros_Listar
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual);
    SELECT f.FiltroId, f.Nombre, f.Procedimiento,
           COALESCE(CAST(ep.value AS nvarchar(200)), f.Procedimiento) AS Consulta,
           f.Parametros, dash.fn_ResolverParametros(f.Parametros, CAST(SYSDATETIMEOFFSET() AS date)) AS ParametrosResueltos,
           f.Compartido, u.Nombre AS Propietario,
           CAST(CASE WHEN f.PropietarioId = @UsuarioId THEN 1 ELSE 0 END AS bit) AS EsMio,
           CAST(CASE WHEN pp.Procedimiento IS NOT NULL THEN 1 ELSE 0 END AS bit) AS PuedoUsar,
           (SELECT COUNT(*) FROM dash.Widget w WHERE w.FiltroId = f.FiltroId) AS Widgets,
           f.FechaCambio
    FROM dash.Filtro f
    JOIN seg.Usuario u ON u.UsuarioId = f.PropietarioId
    LEFT JOIN seg.fn_ProcedimientosPermitidos(@UsuarioId) pp ON pp.Procedimiento = f.Procedimiento
    LEFT JOIN sys.extended_properties ep ON ep.class = 1 AND ep.minor_id = 0 AND ep.name = 'smc:titulo'
                                         AND ep.major_id = OBJECT_ID(N'api.' + QUOTENAME(f.Procedimiento))
    WHERE f.PropietarioId = @UsuarioId OR (f.Compartido = 1 AND pp.Procedimiento IS NOT NULL)
    ORDER BY EsMio DESC, f.Nombre;
END;
GO
