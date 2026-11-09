/* Historial de cambios por issue. Contrato: IdExterno = id del issue y
   {"issueId":"...","histories":[{id, author{accountId}, created, items[{field, fieldId, from, fromString, to, toString}]}]}.
   También acepta "values" (GET /issue/{id}/changelog) y "changeHistories" (POST /changelog/bulkfetch).
   El documento trae el historial completo del issue, así que se reemplaza el anterior. Si una historia viene repetida
   (bulkfetch la repite entre páginas) se integra una sola vez. */
CREATE OR ALTER PROCEDURE sync.Procesar_Changelog
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DocumentoId, i.IssueSk, d.Json
    INTO #k
    FROM #lote l
    JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
    LEFT JOIN ops.Issue i ON i.FuenteId = @FuenteId AND i.IssueId = COALESCE(JSON_VALUE(d.Json, '$.issueId'), d.IdExterno);

    -- El issue aún no se integra: se pospone para la siguiente corrida.
    DELETE l FROM #lote l JOIN #k k ON k.DocumentoId = l.DocumentoId WHERE k.IssueSk IS NULL;
    DELETE FROM #k WHERE IssueSk IS NULL;

    DELETE c FROM ops.IssueCambio c JOIN #k k ON k.IssueSk = c.IssueSk;

    INSERT ops.IssueCambio (FuenteId, HistoriaId, Orden, IssueSk, Fecha, AutorId, CampoId, Campo, Desde, DesdeTexto, Hacia, HaciaTexto)
    SELECT @FuenteId, HistoriaId, Orden, IssueSk, Fecha, AutorId, CampoId, Campo, Desde, DesdeTexto, Hacia, HaciaTexto
    FROM (
    SELECT h.HistoriaId, CAST(it.[key] AS smallint) AS Orden, k.IssueSk, sync.fn_FechaJira(h.Creado) AS Fecha, LEFT(h.AutorId, 128) AS AutorId,
           LEFT(ISNULL(x.CampoId, x.Campo), 100) AS CampoId, LEFT(x.Campo, 255) AS Campo, LEFT(x.Desde, 400) AS Desde,
           LEFT(x.DesdeTexto, 1000) AS DesdeTexto, LEFT(x.Hacia, 400) AS Hacia, LEFT(x.HaciaTexto, 1000) AS HaciaTexto,
           ROW_NUMBER() OVER (PARTITION BY h.HistoriaId, it.[key] ORDER BY k.DocumentoId DESC) AS rn
    FROM #k k
    CROSS APPLY OPENJSON(COALESCE(JSON_QUERY(k.Json, '$.histories'), JSON_QUERY(k.Json, '$.values'), JSON_QUERY(k.Json, '$.changeHistories')))
        WITH (HistoriaId varchar(30) '$.id', Creado nvarchar(60) '$.created', AutorId varchar(200) '$.author.accountId', Items nvarchar(max) '$.items' AS JSON) h
    CROSS APPLY OPENJSON(h.Items) it
    CROSS APPLY OPENJSON(it.value) WITH (CampoId varchar(100) '$.fieldId', Campo nvarchar(255) '$.field',
        Desde nvarchar(4000) '$.from', DesdeTexto nvarchar(4000) '$.fromString', Hacia nvarchar(4000) '$.to', HaciaTexto nvarchar(4000) '$.toString') x
    WHERE h.HistoriaId IS NOT NULL AND sync.fn_FechaJira(h.Creado) IS NOT NULL
    ) c
    WHERE c.rn = 1;
END;
GO
