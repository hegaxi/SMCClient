/* El worker abre una ejecución por entidad. Toma (o renueva) el candado de la fuente;
   si otro proceso lo tiene vigente, falla con el error 50010 y el worker lo intenta después.
   Un worker procesa las entidades de una fuente una por una, así que al abrir una ejecución no
   puede haber otra legítima "corriendo" en la misma fuente. */
CREATE OR ALTER PROCEDURE sync.Ejecucion_Iniciar
    @Fuente           varchar(50),
    @Entidad          varchar(40),
    @Modo             varchar(20),
    @Propietario      nvarchar(200),
    @DuracionCandadoSeg int = 900,
    @EjecucionId      bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente AND Activa = 1);
    IF @FuenteId IS NULL THROW 50011, 'La fuente no existe o está inactiva.', 1;
    IF NOT EXISTS (SELECT 1 FROM cfg.EntidadSync WHERE FuenteId = @FuenteId AND Entidad = @Entidad)
        THROW 50012, 'La entidad no está configurada para la fuente.', 1;

    DECLARE @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();
    BEGIN TRAN;
    MERGE sync.Candado WITH (HOLDLOCK) AS t
    USING (SELECT @FuenteId AS FuenteId) AS s ON t.FuenteId = s.FuenteId
    WHEN MATCHED AND (t.ExpiraEn < @ahora OR t.Propietario = @Propietario OR t.Propietario IS NULL) THEN   -- NULL = liberado
        UPDATE SET Propietario = @Propietario, ExpiraEn = DATEADD(SECOND, @DuracionCandadoSeg, @ahora)
    WHEN NOT MATCHED THEN
        INSERT (FuenteId, Propietario, ExpiraEn) VALUES (@FuenteId, @Propietario, DATEADD(SECOND, @DuracionCandadoSeg, @ahora));

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK;
        THROW 50010, 'Otra instancia está sincronizando esta fuente.', 1;
    END;

    -- Con el candado en la mano, cualquier ejecución que siga "corriendo" en esta fuente es de un proceso que
    -- terminó sin cerrarla (caída del servidor, kill): se cierra para que no confunda al estado ni a los reportes.
    UPDATE sync.Ejecucion
    SET Estado = 'error', Fin = @ahora, Mensaje = N'Abandonada: el proceso terminó sin cerrarla.'
    WHERE FuenteId = @FuenteId AND Estado = 'corriendo';

    INSERT sync.Ejecucion (FuenteId, Entidad, Modo, Servidor) VALUES (@FuenteId, @Entidad, @Modo, @Propietario);
    SET @EjecucionId = SCOPE_IDENTITY();
    COMMIT;
END;
GO
