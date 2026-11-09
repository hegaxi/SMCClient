/* Nivel de jerarquía de Jira (issuetype.hierarchyLevel: 1 épica, 0 estándar, -1 subtarea) en ops.Issue: las horas y el
   avance de una épica se calculan con sus tareas y las subtareas de éstas. Se rellena desde raw.Documento. */
IF COL_LENGTH('ops.Issue', 'NivelJerarquia') IS NULL
    ALTER TABLE ops.Issue ADD NivelJerarquia smallint NOT NULL CONSTRAINT DF_ops_Issue_Nivel DEFAULT 0;
GO
UPDATE i SET NivelJerarquia = COALESCE(TRY_CAST(JSON_VALUE(d.Json, CONCAT(N'$.fields."', t.CampoId, N'".hierarchyLevel')) AS smallint),
                                       CASE WHEN i.EsSubtarea = 1 THEN -1
                                            WHEN JSON_VALUE(d.Json, CONCAT(N'$.fields."', t.CampoId, N'".name')) IN (N'Epic', N'Épica', N'Epica') THEN 1
                                            ELSE 0 END)
FROM ops.Issue i
JOIN raw.Documento d ON d.FuenteId = i.FuenteId AND d.Entidad = 'issue' AND d.IdExterno = i.IssueId
CROSS APPLY (SELECT ISNULL((SELECT CampoId FROM cfg.MapeoCampo m WHERE m.FuenteId = i.FuenteId AND m.Rol = 'tipo_issue'), 'issuetype') AS CampoId) t;
GO
