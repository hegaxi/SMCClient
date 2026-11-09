/* Pantalla "Proyectos a sincronizar": TODOS los proyectos de Jira (también los desactivados), si se sincronizan, cuántos
   issues tienen ya en la base y su última actividad. Segundo resultado: qué pasa con los proyectos nuevos. */
CREATE OR ALTER PROCEDURE api.ProyectosSync_Listar
    @Fuente varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.Codigo AS Fuente, p.Clave, p.Nombre, p.TipoProyecto,
           CAST(CASE WHEN x.ProyectoClave IS NULL THEN 1 ELSE 0 END AS bit) AS Sincronizar,
           n.Issues, n.Abiertos, n.UltimaActualizacion,
           x.Motivo, x.Fecha AS DesactivadoEl
    FROM ops.Proyecto p
    JOIN cfg.Fuente f ON f.FuenteId = p.FuenteId
    LEFT JOIN cfg.ProyectoExcluido x ON x.FuenteId = p.FuenteId AND x.ProyectoClave = p.Clave
    OUTER APPLY (SELECT COUNT(*) AS Issues,
                        SUM(CASE WHEN COALESCE(i.CategoriaEstado, e.Categoria) <> 'done' THEN 1 ELSE 0 END) AS Abiertos,
                        MAX(i.Actualizado) AS UltimaActualizacion
                 FROM ops.Issue i
                 LEFT JOIN ops.Estado e ON e.FuenteId = i.FuenteId AND e.EstadoId = i.EstadoId
                 WHERE i.FuenteId = p.FuenteId AND i.ProyectoId = p.ProyectoId AND i.Eliminado = 0) n
    WHERE p.Eliminado = 0 AND (@Fuente IS NULL OR f.Codigo = @Fuente)
    ORDER BY f.Codigo, p.TipoProyecto, p.Clave;

    SELECT CAST(CASE WHEN ISNULL((SELECT Valor FROM cfg.Parametro WHERE Clave = 'ProyectosNuevosSincronizar'), N'1') = N'0' THEN 0 ELSE 1 END AS bit)
           AS NuevosSeSincronizan;
END;
GO
