/* Antes, el historial y el SLA se pedían solo para los issues que el worker tenía en memoria en esa corrida: si esa
   parte fallaba, nunca se volvían a pedir. Ahora el pendiente vive en sync.IssuePendiente. Esta migración encola los
   issues que nunca recibieron su historial (o su SLA, en mesa de ayuda): la siguiente corrida del worker los trae. */
INSERT sync.IssuePendiente (FuenteId, Entidad, IssueId, Clave, TipoProyecto)
SELECT i.FuenteId, e.Entidad, i.IssueId, i.Clave, p.TipoProyecto
FROM ops.Issue i
LEFT JOIN ops.Proyecto p ON p.FuenteId = i.FuenteId AND p.ProyectoId = i.ProyectoId
JOIN cfg.EntidadSync e ON e.FuenteId = i.FuenteId AND e.Activa = 1 AND e.Modo = 'dependiente'
WHERE i.Eliminado = 0
  AND (JSON_VALUE(e.Parametros, '$.soloTipoProyecto') IS NULL OR p.TipoProyecto IS NULL
       OR p.TipoProyecto = JSON_VALUE(e.Parametros, '$.soloTipoProyecto'))
  AND NOT EXISTS (SELECT 1 FROM raw.Documento d WHERE d.FuenteId = i.FuenteId AND d.Entidad = e.Entidad AND d.IdExterno = i.IssueId)
  AND NOT EXISTS (SELECT 1 FROM sync.IssuePendiente x WHERE x.FuenteId = i.FuenteId AND x.Entidad = e.Entidad AND x.IssueId = i.IssueId);
GO
