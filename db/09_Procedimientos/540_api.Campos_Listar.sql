/* Catálogo de campos de Jira con su rol (si tiene). La interfaz lo usa para columnas y filtros dinámicos. */
CREATE OR ALTER PROCEDURE api.Campos_Listar
    @Fuente      varchar(50) = NULL,
    @SoloActivos bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.Codigo AS Fuente, c.CampoId, c.Nombre, c.EsCustom, c.TipoSchema, c.ItemsSchema, c.TipoCustom,
           c.GuardarValor, c.Activo, c.PrimeraVez, c.FechaBaja,
           STUFF((SELECT N', ' + m.Rol FROM cfg.MapeoCampo m WHERE m.FuenteId = c.FuenteId AND m.CampoId = c.CampoId FOR XML PATH('')), 1, 2, N'') AS Roles
    FROM meta.CampoJira c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId
    WHERE (@Fuente IS NULL OR f.Codigo = @Fuente) AND (@SoloActivos = 0 OR c.Activo = 1)
    ORDER BY f.Codigo, c.EsCustom, c.Nombre;
END;
GO
