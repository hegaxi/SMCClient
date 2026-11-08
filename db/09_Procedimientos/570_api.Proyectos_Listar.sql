CREATE OR ALTER PROCEDURE api.Proyectos_Listar
    @TipoProyecto varchar(30) = NULL     -- software | service_desk | business
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.Codigo AS Fuente, p.Clave, p.Nombre, p.TipoProyecto,
           (SELECT COUNT(*) FROM ops.Issue i WHERE i.FuenteId = p.FuenteId AND i.ProyectoId = p.ProyectoId AND i.Eliminado = 0) AS Issues
    FROM ops.Proyecto p JOIN cfg.Fuente f ON f.FuenteId = p.FuenteId
    WHERE p.Eliminado = 0 AND (@TipoProyecto IS NULL OR p.TipoProyecto = @TipoProyecto)
    ORDER BY p.TipoProyecto, p.Clave;
END;
GO
