/* Id de Jira del padre en ops.Issue: la jerarquía (épica → tarea → subtarea) se unía por la clave visible, que cambia
   cuando un issue se mueve de proyecto; el id no. Se rellena desde el último JSON de cada issue en raw.Documento. */
IF COL_LENGTH('ops.Issue', 'PadreId') IS NULL
    ALTER TABLE ops.Issue ADD PadreId varchar(30) NULL;
GO
UPDATE i SET PadreId = CAST(JSON_VALUE(d.Json, CONCAT(N'$.fields."', t.CampoId, N'".id')) AS varchar(30))
FROM ops.Issue i
JOIN raw.Documento d ON d.FuenteId = i.FuenteId AND d.Entidad = 'issue' AND d.IdExterno = i.IssueId
CROSS APPLY (SELECT ISNULL((SELECT CampoId FROM cfg.MapeoCampo m WHERE m.FuenteId = i.FuenteId AND m.Rol = 'padre'), 'parent') AS CampoId) t
WHERE i.PadreId IS NULL AND i.PadreClave IS NOT NULL;
GO
-- El índice de hijos se creaba por clave en versiones anteriores de este cambio: se rehace por id.
IF EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
           WHERE ic.object_id = OBJECT_ID('ops.Issue') AND ic.index_id = INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Padre', 'IndexId')
             AND c.name = 'PadreClave' AND ic.key_ordinal > 0)
    DROP INDEX IX_ops_Issue_Padre ON ops.Issue;
GO
