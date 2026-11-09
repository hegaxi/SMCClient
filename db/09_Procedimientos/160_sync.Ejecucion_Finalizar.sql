/* Cierra la ejecución. Si terminó bien y es carga inicial, incremental o catálogo, avanza la marca
   de agua al máximo 'Actualizado' visto (nunca la retrocede). Un backfill o una conciliación
   no la mueven porque solo vieron una parte de los datos. */
CREATE OR ALTER PROCEDURE sync.Ejecucion_Finalizar
    @EjecucionId bigint,
    @Estado      varchar(15),
    @Mensaje     nvarchar(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int, @Entidad varchar(40), @Modo varchar(20);
    SELECT @FuenteId = FuenteId, @Entidad = Entidad, @Modo = Modo FROM sync.Ejecucion WHERE EjecucionId = @EjecucionId;
    IF @FuenteId IS NULL THROW 50030, 'La ejecución no existe.', 1;

    DECLARE @errores int = (SELECT COUNT(*) FROM raw.Documento WHERE LoteId = @EjecucionId AND Procesado = 0 AND ErrorProceso IS NOT NULL);
    IF @Estado = 'ok' AND @errores > 0 SET @Estado = 'parcial';

    BEGIN TRAN;
    UPDATE sync.Ejecucion
    SET Fin = SYSDATETIMEOFFSET(), Estado = @Estado, Mensaje = @Mensaje, Errores = @errores,
        Procesados = (SELECT COUNT(*) FROM raw.Documento WHERE LoteId = @EjecucionId AND Procesado = 1)
    WHERE EjecucionId = @EjecucionId;

    IF @Estado IN ('ok', 'parcial') AND @Modo IN ('inicial', 'incremental', 'catalogo')
    BEGIN
        DECLARE @max datetimeoffset(3) = (SELECT MAX(Actualizado) FROM raw.Documento WHERE LoteId = @EjecucionId);
        MERGE sync.MarcaAgua AS t
        USING (SELECT @FuenteId AS FuenteId, @Entidad AS Entidad) AS s ON t.FuenteId = s.FuenteId AND t.Entidad = s.Entidad
        WHEN MATCHED THEN UPDATE SET
            Valor = CASE WHEN @max IS NULL THEN t.Valor WHEN t.Valor IS NULL OR @max > t.Valor THEN @max ELSE t.Valor END,
            EjecucionId = @EjecucionId, ActualizadoEn = SYSDATETIMEOFFSET()
        WHEN NOT MATCHED THEN INSERT (FuenteId, Entidad, Valor, EjecucionId) VALUES (@FuenteId, @Entidad, @max, @EjecucionId);
    END;
    COMMIT;
END;
GO
