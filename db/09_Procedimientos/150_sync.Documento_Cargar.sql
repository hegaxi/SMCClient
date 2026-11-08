/* Recibe una página de documentos JSON (TVP) y la guarda en raw.Documento.
   Si el documento no cambió (mismo hash) solo se marca como visto en este lote: no se reprocesa. */
CREATE OR ALTER PROCEDURE sync.Documento_Cargar
    @EjecucionId bigint,
    @Documentos  sync.DocumentoTipo READONLY,
    @Cambiados   int = NULL OUTPUT        -- documentos nuevos o modificados (los iguales no se reprocesan)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int, @Entidad varchar(40);
    SELECT @FuenteId = FuenteId, @Entidad = Entidad FROM sync.Ejecucion WHERE EjecucionId = @EjecucionId AND Estado = 'corriendo';
    IF @FuenteId IS NULL THROW 50020, 'La ejecución no existe o ya terminó.', 1;

    DECLARE @malos int = (SELECT COUNT(*) FROM @Documentos WHERE ISJSON(Json) = 0);
    IF @malos > 0 THROW 50021, 'Hay documentos que no son JSON válido.', 1;

    SELECT IdExterno, Actualizado, Json, HASHBYTES('SHA2_256', Json) AS Hash
    INTO #in FROM @Documentos;

    DECLARE @nCambiados int = 0;
    BEGIN TRAN;
    UPDATE d SET Json = i.Json, Hash = i.Hash, Actualizado = i.Actualizado, LoteId = @EjecucionId,
                 Recibido = SYSDATETIMEOFFSET(), Procesado = 0, ProcesadoEn = NULL, Intentos = 0, ErrorProceso = NULL
    FROM raw.Documento d JOIN #in i ON d.FuenteId = @FuenteId AND d.Entidad = @Entidad AND d.IdExterno = i.IdExterno
    WHERE d.Hash <> i.Hash;
    SET @nCambiados += @@ROWCOUNT;

    UPDATE d SET LoteId = @EjecucionId
    FROM raw.Documento d JOIN #in i ON d.FuenteId = @FuenteId AND d.Entidad = @Entidad AND d.IdExterno = i.IdExterno
    WHERE d.Hash = i.Hash;

    INSERT raw.Documento (FuenteId, Entidad, IdExterno, Actualizado, Hash, Json, LoteId)
    SELECT @FuenteId, @Entidad, i.IdExterno, i.Actualizado, i.Hash, i.Json, @EjecucionId
    FROM #in i
    WHERE NOT EXISTS (SELECT 1 FROM raw.Documento d WHERE d.FuenteId = @FuenteId AND d.Entidad = @Entidad AND d.IdExterno = i.IdExterno);
    SET @nCambiados += @@ROWCOUNT;

    UPDATE sync.Ejecucion SET Leidos += (SELECT COUNT(*) FROM #in), Cambiados += @nCambiados WHERE EjecucionId = @EjecucionId;
    COMMIT;

    SET @Cambiados = @nCambiados;
END;
GO
