/* Catálogo de proyectos (GET /rest/api/3/project/search, un documento por proyecto). Un proyecto que aparece por
   primera vez queda desactivado (cfg.ProyectoExcluido) si cfg.Parametro ProyectosNuevosSincronizar = 0; nunca en la
   primera carga de la fuente, para no dejarla sin proyectos. */
CREATE OR ALTER PROCEDURE sync.Procesar_Proyectos
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @nuevos TABLE (Clave varchar(50));
    DECLARE @habiaProyectos bit = CASE WHEN EXISTS (SELECT 1 FROM ops.Proyecto WHERE FuenteId = @FuenteId) THEN 1 ELSE 0 END;
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
                          VALUES (@FuenteId, s.ProyectoId, s.Clave, s.Nombre, s.TipoProyecto, s.Estilo)
    OUTPUT CASE WHEN $action = 'INSERT' THEN inserted.Clave END INTO @nuevos (Clave);

    IF @habiaProyectos = 1 AND (SELECT Valor FROM cfg.Parametro WHERE Clave = 'ProyectosNuevosSincronizar') = N'0'
        INSERT cfg.ProyectoExcluido (FuenteId, ProyectoClave, Motivo)
        SELECT DISTINCT @FuenteId, n.Clave, N'Proyecto nuevo en Jira: actívelo en Proyectos a sincronizar si se necesita.'
        FROM @nuevos n
        WHERE n.Clave IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM cfg.ProyectoExcluido x WHERE x.FuenteId = @FuenteId AND x.ProyectoClave = n.Clave);
END;
GO
