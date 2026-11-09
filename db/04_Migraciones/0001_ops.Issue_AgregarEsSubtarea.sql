/* Marca de subtarea en ops.Issue: en Scrum las personas registran el tiempo en las subtareas, y para ver el tiempo
   de una historia hay que sumar el de sus subtareas. Se rellena con el último JSON de cada issue en raw.Documento
   (sin volver a llamar a Jira). */
IF COL_LENGTH('ops.Issue', 'EsSubtarea') IS NULL
    ALTER TABLE ops.Issue ADD EsSubtarea bit NOT NULL CONSTRAINT DF_ops_Issue_EsSubtarea DEFAULT 0;
GO
UPDATE i SET EsSubtarea = 1
FROM ops.Issue i
JOIN raw.Documento d ON d.FuenteId = i.FuenteId AND d.Entidad = 'issue' AND d.IdExterno = i.IssueId
OUTER APPLY (SELECT CampoId FROM cfg.MapeoCampo m WHERE m.FuenteId = i.FuenteId AND m.Rol = 'tipo_issue') m
WHERE i.EsSubtarea = 0
  AND JSON_VALUE(d.Json, CONCAT(N'$.fields."', ISNULL(m.CampoId, 'issuetype'), N'".subtask')) = 'true';
GO
