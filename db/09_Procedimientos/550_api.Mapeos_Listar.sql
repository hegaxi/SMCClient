CREATE OR ALTER PROCEDURE api.Mapeos_Listar
    @Fuente varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.Codigo AS Fuente, r.Rol, r.Descripcion, r.Obligatorio, m.CampoId, c.Nombre AS Campo, c.Activo AS CampoActivo,
           m.Origen, m.FechaResolucion
    FROM cfg.Fuente f
    CROSS JOIN cfg.RolCampo r
    LEFT JOIN cfg.MapeoCampo m ON m.FuenteId = f.FuenteId AND m.Rol = r.Rol
    LEFT JOIN meta.CampoJira c ON c.FuenteId = f.FuenteId AND c.CampoId = m.CampoId
    WHERE f.Activa = 1 AND (@Fuente IS NULL OR f.Codigo = @Fuente)
    ORDER BY f.Codigo, r.Obligatorio DESC, r.Rol;
END;
GO
