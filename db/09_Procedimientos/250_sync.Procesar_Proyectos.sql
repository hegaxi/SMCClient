/* Catálogo de proyectos (GET /rest/api/3/project/search, un documento por proyecto). */
CREATE OR ALTER PROCEDURE sync.Procesar_Proyectos
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    MERGE ops.Proyecto AS t
    USING (
        SELECT j.ProyectoId, j.Clave, j.Nombre, j.TipoProyecto, j.Estilo
        FROM #lote l JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
        CROSS APPLY OPENJSON(d.Json) WITH (
            ProyectoId varchar(30) '$.id', Clave varchar(50) '$.key', Nombre nvarchar(255) '$.name',
            TipoProyecto varchar(30) '$.projectTypeKey', Estilo varchar(20) '$.style') j
        WHERE j.ProyectoId IS NOT NULL
    ) AS s ON t.FuenteId = @FuenteId AND t.ProyectoId = s.ProyectoId
    WHEN MATCHED THEN UPDATE SET Clave = s.Clave, Nombre = s.Nombre, TipoProyecto = s.TipoProyecto, Estilo = s.Estilo,
                                 Eliminado = 0, Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, ProyectoId, Clave, Nombre, TipoProyecto, Estilo)
                          VALUES (@FuenteId, s.ProyectoId, s.Clave, s.Nombre, s.TipoProyecto, s.Estilo);
END;
GO
