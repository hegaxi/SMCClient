/* Comentarios (GET /rest/api/2/issue/{id}/comment, todas las páginas). Contrato: un documento por issue con TODOS sus
   comentarios: {"issueId":"...","comments":[{id, author, body, jsdPublic, created, updated}, ...]}; IdExterno = id del
   issue. Los comentarios que ya no vienen se borraron en Jira. jsdPublic: true = lo ve el cliente; false = nota interna. */
CREATE OR ALTER PROCEDURE sync.Procesar_Comentarios
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DocumentoId, CAST(COALESCE(JSON_VALUE(d.Json, '$.issueId'), d.IdExterno) AS varchar(30)) AS IssueId, d.Json
    INTO #d
    FROM #lote l JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId;

    SELECT d.IssueId, c.*
    INTO #c
    FROM #d d
    CROSS APPLY OPENJSON(d.Json, '$.comments') WITH (
        ComentarioId varchar(30) '$.id',
        AutorId varchar(200) '$.author.accountId', AutorNombre nvarchar(255) '$.author.displayName', AutorTipo varchar(20) '$.author.accountType',
        Cuerpo nvarchar(max) '$.body', Publico varchar(10) '$.jsdPublic', Creado nvarchar(60) '$.created', Actualizado nvarchar(60) '$.updated') c;

    IF EXISTS (SELECT 1 FROM #c WHERE ComentarioId IS NULL) THROW 50060, 'Comentario sin id.', 1;

    MERGE ops.Usuario AS t
    USING (
        SELECT AccountId, Nombre, TipoCuenta FROM (
            SELECT LEFT(AutorId, 128) AS AccountId, AutorNombre AS Nombre, AutorTipo AS TipoCuenta,
                   ROW_NUMBER() OVER (PARTITION BY AutorId ORDER BY (SELECT NULL)) AS rn
            FROM #c WHERE AutorId IS NOT NULL) q WHERE rn = 1
    ) AS s ON t.FuenteId = @FuenteId AND t.AccountId = s.AccountId
    WHEN MATCHED THEN UPDATE SET Nombre = ISNULL(s.Nombre, t.Nombre), TipoCuenta = ISNULL(s.TipoCuenta, t.TipoCuenta), Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, AccountId, Nombre, TipoCuenta) VALUES (@FuenteId, s.AccountId, s.Nombre, s.TipoCuenta);

    MERGE ops.Comentario AS t
    USING (
        SELECT * FROM (
            SELECT ComentarioId, IssueId, LEFT(AutorId, 128) AS AutorId, Cuerpo,
                   CAST(CASE Publico WHEN 'true' THEN 1 WHEN 'false' THEN 0 END AS bit) AS Publico,
                   sync.fn_FechaJira(Creado) AS Creado, sync.fn_FechaJira(Actualizado) AS Actualizado,
                   ROW_NUMBER() OVER (PARTITION BY ComentarioId ORDER BY (SELECT NULL)) AS rn
            FROM #c) x WHERE rn = 1
    ) AS s ON t.FuenteId = @FuenteId AND t.ComentarioId = s.ComentarioId
    WHEN MATCHED THEN UPDATE SET IssueId = s.IssueId, AutorId = s.AutorId, Cuerpo = s.Cuerpo, Publico = s.Publico,
        Creado = s.Creado, Actualizado = s.Actualizado, Eliminado = 0
    WHEN NOT MATCHED THEN INSERT (FuenteId, ComentarioId, IssueId, AutorId, Cuerpo, Publico, Creado, Actualizado)
        VALUES (@FuenteId, s.ComentarioId, s.IssueId, s.AutorId, s.Cuerpo, s.Publico, s.Creado, s.Actualizado);

    -- El documento trae todos los comentarios del issue: los que ya no vienen se borraron en Jira.
    UPDATE c SET Eliminado = 1
    FROM ops.Comentario c JOIN #d d ON c.FuenteId = @FuenteId AND c.IssueId = d.IssueId
    WHERE c.Eliminado = 0 AND NOT EXISTS (SELECT 1 FROM #c x WHERE x.ComentarioId = c.ComentarioId);
END;
GO
