/* Proyectos que ya no aparecen en el catálogo completo: se marcan como eliminados (no se borran).
   Ojo: el catálogo depende de los permisos del usuario técnico de Jira. Si le quitan acceso a un
   proyecto, aparecerá como eliminado; por eso se avisa. Mismo umbral de protección que los campos. */
CREATE OR ALTER PROCEDURE sync.Cerrar_Proyectos
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM sync.Ejecucion WHERE EjecucionId = @EjecucionId AND Entidad = 'proyecto' AND Modo = 'catalogo') RETURN;

    DECLARE @umbral int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'UmbralBajaCatalogoPct') AS int), 50);
    DECLARE @vistos int = (SELECT COUNT(*) FROM raw.Documento WHERE FuenteId = @FuenteId AND Entidad = 'proyecto' AND LoteId = @EjecucionId);
    DECLARE @activos int = (SELECT COUNT(*) FROM ops.Proyecto WHERE FuenteId = @FuenteId AND Eliminado = 0);
    DECLARE @msg nvarchar(1000), @datos nvarchar(max);

    IF @activos > 0 AND @vistos * 100 < @activos * @umbral
    BEGIN
        SET @msg = CONCAT(N'El catálogo de proyectos llegó con ', @vistos, N' de ', @activos, N'. No se marcó ninguno como eliminado.');
        EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'proyecto.catalogo_incompleto', @msg;
        RETURN;
    END;

    SELECT p.ProyectoId, p.Clave INTO #bajas
    FROM ops.Proyecto p
    WHERE p.FuenteId = @FuenteId AND p.Eliminado = 0
      AND NOT EXISTS (SELECT 1 FROM raw.Documento d WHERE d.FuenteId = @FuenteId AND d.Entidad = 'proyecto' AND d.LoteId = @EjecucionId AND d.IdExterno = p.ProyectoId);

    IF EXISTS (SELECT 1 FROM #bajas)
    BEGIN
        UPDATE p SET Eliminado = 1, Actualizado = SYSDATETIMEOFFSET()
        FROM ops.Proyecto p JOIN #bajas b ON p.FuenteId = @FuenteId AND p.ProyectoId = b.ProyectoId;
        SET @datos = (SELECT ProyectoId, Clave FROM #bajas FOR JSON PATH);
        EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'proyecto.baja',
             N'Uno o más proyectos ya no son visibles en Jira (eliminados, archivados o sin permiso para el usuario técnico).', @datos;
    END;
END;
GO
