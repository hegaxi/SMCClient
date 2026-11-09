/* Issue con sus catálogos resueltos. Base de casi todos los reportes.
   Oculta los issues eliminados y los de proyectos excluidos (cfg.ProyectoExcluido). */
CREATE OR ALTER VIEW rpt.vIssue
AS
SELECT
    i.IssueSk, i.FuenteId, i.IssueId, i.Clave,
    i.ProyectoId, p.Clave AS ProyectoClave, p.Nombre AS ProyectoNombre, p.TipoProyecto,
    i.TipoIssueId, i.TipoIssue,
    i.EstadoId, COALESCE(e.Nombre, N'') AS Estado, COALESCE(i.CategoriaEstado, e.Categoria) AS CategoriaEstado,
    CAST(CASE WHEN COALESCE(i.CategoriaEstado, e.Categoria) = 'done' THEN 0 ELSE 1 END AS bit) AS Abierto,
    i.PrioridadId, i.Prioridad, i.ResolucionId, i.Resolucion,
    i.ResponsableId, ur.Nombre AS Responsable,
    i.InformanteId, ui.Nombre AS Informante, ui.TipoCuenta AS TipoCuentaInformante,
    i.Resumen, i.PadreClave, i.EsSubtarea, i.TipoSolicitudId, i.TipoSolicitud, i.StoryPoints,
    i.TiempoInvertidoSeg, i.EstimacionOriginalSeg, i.EstimacionRestanteSeg,
    i.Creado, i.Actualizado, i.Resuelto, i.Vencimiento
FROM ops.Issue i
LEFT JOIN ops.Proyecto p ON p.FuenteId = i.FuenteId AND p.ProyectoId = i.ProyectoId
LEFT JOIN ops.Estado   e ON e.FuenteId = i.FuenteId AND e.EstadoId   = i.EstadoId
LEFT JOIN ops.Usuario ur ON ur.FuenteId = i.FuenteId AND ur.AccountId = i.ResponsableId
LEFT JOIN ops.Usuario ui ON ui.FuenteId = i.FuenteId AND ui.AccountId = i.InformanteId
WHERE i.Eliminado = 0
  AND NOT EXISTS (SELECT 1 FROM cfg.ProyectoExcluido x WHERE x.FuenteId = i.FuenteId AND x.ProyectoClave = p.Clave);
GO
