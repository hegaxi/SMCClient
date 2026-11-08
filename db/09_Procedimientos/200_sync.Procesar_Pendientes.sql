/* Orquestador de integración. Recorre las entidades en el orden de cfg.EntidadSync y, por lotes,
   llama al procedimiento sync.Procesar_* de cada una. Los procedimientos trabajan sobre #lote.

   Resiliencia:
   - Cada lote es una transacción. Si falla, sus documentos se reintentan UNO POR UNO; así un
     documento malo no frena a los demás. Tras MaxIntentosDocumento fallos queda en cuarentena
     (Procesado = 0, ErrorProceso con el motivo) y se avisa en sync.Evento.
   - Un Procesar_* puede sacar documentos de #lote para posponerlos (p. ej. un worklog cuyo issue
     aún no llega): quedan pendientes para la siguiente corrida.
   - Al terminar una entidad de tipo catálogo se llama su ProcedimientoCierre (bajas, mapeos). */
CREATE OR ALTER PROCEDURE sync.Procesar_Pendientes
    @FuenteId    int = NULL,
    @EjecucionId bigint = NULL,
    @Entidad     varchar(40) = NULL,
    @Procesados  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @tamano int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'TamanoLoteProceso') AS int), 200);
    DECLARE @maxIntentos tinyint = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'MaxIntentosDocumento') AS tinyint), 3);

    CREATE TABLE #lote (DocumentoId bigint NOT NULL PRIMARY KEY);
    CREATE TABLE #vistos (DocumentoId bigint NOT NULL PRIMARY KEY);

    DECLARE @f int, @ent varchar(40), @proc sysname, @cierre sysname, @n int, @tomar int, @err nvarchar(2000), @nProcesados int = 0;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT e.FuenteId, e.Entidad, e.Procedimiento, e.ProcedimientoCierre
        FROM cfg.EntidadSync e JOIN cfg.Fuente fu ON fu.FuenteId = e.FuenteId
        WHERE e.Activa = 1 AND fu.Activa = 1
          AND (@FuenteId IS NULL OR e.FuenteId = @FuenteId)
          AND (@Entidad IS NULL OR e.Entidad = @Entidad)
        ORDER BY e.FuenteId, e.Orden;
    OPEN c; FETCH c INTO @f, @ent, @proc, @cierre;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Solo se ejecutan procedimientos del esquema sync llamados Procesar_* / Cerrar_*.
        IF OBJECT_ID(@proc, 'P') IS NULL OR OBJECT_SCHEMA_NAME(OBJECT_ID(@proc)) <> 'sync' OR OBJECT_NAME(OBJECT_ID(@proc)) NOT LIKE 'Procesar[_]%'
        BEGIN
            SET @err = CONCAT(N'Procedimiento de integración inválido: ', @proc);
            EXEC sync.Evento_Registrar @f, @EjecucionId, 'error', 'config.procedimiento', @err;
            FETCH c INTO @f, @ent, @proc, @cierre; CONTINUE;
        END;

        WHILE 1 = 1
        BEGIN
            TRUNCATE TABLE #lote;
            SET @tomar = CASE WHEN EXISTS (SELECT 1 FROM raw.Documento d WHERE d.FuenteId = @f AND d.Entidad = @ent AND d.Procesado = 0
                                             AND d.Intentos BETWEEN 1 AND @maxIntentos - 1
                                             AND NOT EXISTS (SELECT 1 FROM #vistos v WHERE v.DocumentoId = d.DocumentoId))
                              THEN 1 ELSE @tamano END;
            INSERT #lote (DocumentoId)
            SELECT TOP (@tomar) d.DocumentoId FROM raw.Documento d
            WHERE d.FuenteId = @f AND d.Entidad = @ent AND d.Procesado = 0 AND d.Intentos < @maxIntentos
              AND NOT EXISTS (SELECT 1 FROM #vistos v WHERE v.DocumentoId = d.DocumentoId)
            ORDER BY d.Intentos DESC, d.DocumentoId;
            SET @n = @@ROWCOUNT;
            IF @n = 0 BREAK;
            INSERT #vistos SELECT DocumentoId FROM #lote;

            BEGIN TRY
                BEGIN TRAN;
                EXEC @proc @FuenteId = @f, @EjecucionId = @EjecucionId;
                UPDATE d SET Procesado = 1, ProcesadoEn = SYSDATETIMEOFFSET(), ErrorProceso = NULL
                FROM raw.Documento d JOIN #lote l ON l.DocumentoId = d.DocumentoId;
                SET @nProcesados += @@ROWCOUNT;
                COMMIT;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK;
                SET @err = LEFT(CONCAT(ERROR_PROCEDURE(), N' línea ', ERROR_LINE(), N': ', ERROR_MESSAGE()), 2000);
                -- El ROLLBACK también deshace los cambios a #lote: contiene exactamente lo que se tomó.
                UPDATE d SET Intentos = d.Intentos + 1, ErrorProceso = @err
                FROM raw.Documento d JOIN #lote l ON l.DocumentoId = d.DocumentoId;
                IF @n > 1
                    -- Se reintentan uno por uno en esta misma corrida para aislar al documento con problema.
                    DELETE v FROM #vistos v JOIN #lote l ON l.DocumentoId = v.DocumentoId;
                ELSE
                BEGIN
                    DECLARE @datos nvarchar(400) = (SELECT TOP (1) CONCAT(N'{"entidad":"', d.Entidad, N'","idExterno":"', d.IdExterno, N'"}')
                                                    FROM raw.Documento d JOIN #lote l ON l.DocumentoId = d.DocumentoId);
                    EXEC sync.Evento_Registrar @f, @EjecucionId, 'error', 'documento.error', @err, @datos;
                END;
            END CATCH;
        END;

        IF @cierre IS NOT NULL
        BEGIN
            IF OBJECT_ID(@cierre, 'P') IS NOT NULL AND OBJECT_SCHEMA_NAME(OBJECT_ID(@cierre)) = 'sync' AND OBJECT_NAME(OBJECT_ID(@cierre)) LIKE 'Cerrar[_]%'
            BEGIN TRY
                EXEC @cierre @FuenteId = @f, @EjecucionId = @EjecucionId;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK;
                SET @err = LEFT(CONCAT(ERROR_PROCEDURE(), N': ', ERROR_MESSAGE()), 2000);
                EXEC sync.Evento_Registrar @f, @EjecucionId, 'error', 'cierre.error', @err;
            END CATCH;
        END;

        FETCH c INTO @f, @ent, @proc, @cierre;
    END;
    CLOSE c; DEALLOCATE c;

    SET @Procesados = @nProcesados;
END;
GO
