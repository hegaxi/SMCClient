/* GET /rest/api/3/worklog/deleted: {"worklogId":123,"updatedTime":...}. Se marca, no se borra. */
CREATE OR ALTER PROCEDURE sync.Procesar_WorklogsEliminados
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE w SET Eliminado = 1
    FROM ops.Worklog w
    JOIN (
        SELECT CAST(COALESCE(JSON_VALUE(d.Json, '$.worklogId'), d.IdExterno) AS varchar(30)) AS WorklogId
        FROM #lote l JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
    ) x ON w.FuenteId = @FuenteId AND w.WorklogId = x.WorklogId;
END;
GO
