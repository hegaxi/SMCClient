/* Una consulta personalizada (si el usuario puede verla): 1) su definición; 2) los campos que usa (columnas y criterios)
   con su etiqueta, para mostrarla y ordenar por columna. */
CREATE OR ALTER PROCEDURE api.ConsultaPersonalizada_Obtener
    @ConsultaId    int,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    DECLARE @admin bit = seg.fn_EsAdministrador(@u);
    IF NOT EXISTS (SELECT 1 FROM dash.Consulta WHERE ConsultaId = @ConsultaId) THROW 50404, 'La consulta no existe.', 1;
    IF @u IS NULL OR (@admin = 0 AND NOT EXISTS (
        SELECT 1 FROM dash.ConsultaAcceso x WHERE x.ConsultaId = @ConsultaId
          AND ((x.Tipo = 'U' AND x.Id = @u) OR (x.Tipo = 'R' AND x.Id IN (SELECT RolId FROM seg.UsuarioRol WHERE UsuarioId = @u)))))
        THROW 50403, 'No tiene acceso a esta consulta.', 1;

    SELECT c.ConsultaId, c.Nombre, c.Descripcion, c.Criterios, c.Columnas, c.OrdenarPor, c.Descendente,
           CASE WHEN @admin = 1 THEN (SELECT STRING_AGG(CASE x.Tipo WHEN 'U' THEN us.Login ELSE N'rol:' + r.Nombre END, N', ')
                                      FROM dash.ConsultaAcceso x
                                      LEFT JOIN seg.Usuario us ON x.Tipo = 'U' AND us.UsuarioId = x.Id
                                      LEFT JOIN seg.Rol r ON x.Tipo = 'R' AND r.RolId = x.Id
                                      WHERE x.ConsultaId = c.ConsultaId) END AS CompartidaCon,
           @admin AS PuedoEditar,
           seg.fn_EsExterno(@u) AS SoloMiOrganizacion
    FROM dash.Consulta c WHERE c.ConsultaId = @ConsultaId;

    DECLARE @crit nvarchar(max), @cols nvarchar(2000);
    SELECT @crit = Criterios, @cols = Columnas FROM dash.Consulta WHERE ConsultaId = @ConsultaId;
    SELECT f.Clave, f.Etiqueta, f.Tipo, f.Alias, CAST(CASE WHEN f.ExpresionMulti IS NOT NULL THEN 1 ELSE 0 END AS bit) AS Multivalor
    FROM rpt.fn_CamposBuscador() f
    WHERE f.Clave IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(ISNULL(@cols, N''), ','))
       OR (NULLIF(LTRIM(RTRIM(@cols)), N'') IS NULL AND f.ColumnaPredeterminada = 1)
       OR f.Clave = 'clave'
       OR f.Clave IN (SELECT JSON_VALUE(j.value, '$.campo') COLLATE DATABASE_DEFAULT FROM OPENJSON(@crit) j);
END;
GO
