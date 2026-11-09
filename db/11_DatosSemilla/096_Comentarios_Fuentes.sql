/* Comentarios: agrega la entidad a las fuentes registradas antes de que existiera (sync.Fuente_Registrar ya la incluye
   para las nuevas) y encola el historial de comentarios de los issues que aún no lo tienen; la siguiente corrida del
   worker los trae. Si ya están, no hace nada. */
INSERT cfg.EntidadSync (FuenteId, Entidad, Orden, Modo, FrecuenciaMin, Endpoint, TamanoLote, Procedimiento, ProcedimientoCierre, Parametros)
SELECT f.FuenteId, 'comentario', 90, 'dependiente', 15, N'/rest/api/2/issue/{issueIdOrKey}/comment', 50, N'sync.Procesar_Comentarios', NULL, NULL
FROM cfg.Fuente f
WHERE NOT EXISTS (SELECT 1 FROM cfg.EntidadSync e WHERE e.FuenteId = f.FuenteId AND e.Entidad = 'comentario');

INSERT sync.IssuePendiente (FuenteId, Entidad, IssueId, Clave)
SELECT i.FuenteId, 'comentario', i.IssueId, i.Clave
FROM ops.Issue i
JOIN cfg.EntidadSync e ON e.FuenteId = i.FuenteId AND e.Entidad = 'comentario' AND e.Activa = 1
WHERE i.Eliminado = 0
  AND NOT EXISTS (SELECT 1 FROM raw.Documento d WHERE d.FuenteId = i.FuenteId AND d.Entidad = 'comentario' AND d.IdExterno = i.IssueId)
  AND NOT EXISTS (SELECT 1 FROM sync.IssuePendiente p WHERE p.FuenteId = i.FuenteId AND p.Entidad = 'comentario' AND p.IssueId = i.IssueId);
GO
