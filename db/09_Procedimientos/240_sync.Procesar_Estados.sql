/* Catálogo de estados (GET /rest/api/3/status). */
CREATE OR ALTER PROCEDURE sync.Procesar_Estados
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    MERGE ops.Estado AS t
    USING (
        SELECT DISTINCT j.EstadoId, j.Nombre, j.Categoria
        FROM #lote l JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
        CROSS APPLY OPENJSON(d.Json) WITH (EstadoId varchar(30) '$.id', Nombre nvarchar(255) '$.name', Categoria varchar(20) '$.statusCategory.key') j
        WHERE j.EstadoId IS NOT NULL
    ) AS s ON t.FuenteId = @FuenteId AND t.EstadoId = s.EstadoId
    WHEN MATCHED THEN UPDATE SET Nombre = ISNULL(s.Nombre, t.Nombre), Categoria = ISNULL(s.Categoria, t.Categoria), Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, EstadoId, Nombre, Categoria) VALUES (@FuenteId, s.EstadoId, ISNULL(s.Nombre, s.EstadoId), s.Categoria);
END;
GO
