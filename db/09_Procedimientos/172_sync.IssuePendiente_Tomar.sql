/* Entrega al worker hasta @Max issues pendientes de una entidad (changelog, sla, padre) y registra el intento.
   Los que fallaron 5 veces seguidas se reintentan una vez al día (no se insiste cada ciclo con algo que no existe).
   @TomadoEn se devuelve para que IssuePendiente_Completar no borre un pendiente que se volvió a encolar después. */
CREATE OR ALTER PROCEDURE sync.IssuePendiente_Tomar
    @Fuente   varchar(50),
    @Entidad  varchar(40),
    @Max      int = 2000,
    @TomadoEn datetimeoffset(3) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50404, 'La fuente no existe.', 1;
    IF @Max IS NULL OR @Max < 1 SET @Max = 2000;
    SET @TomadoEn = SYSDATETIMEOFFSET();

    UPDATE t SET Intentos = t.Intentos + 1, UltimoIntento = @TomadoEn
    OUTPUT inserted.IssueId, inserted.Clave, inserted.TipoProyecto
    FROM (SELECT TOP (@Max) * FROM sync.IssuePendiente
          WHERE FuenteId = @FuenteId AND Entidad = @Entidad
            AND (Intentos < 5 OR UltimoIntento < DATEADD(DAY, -1, @TomadoEn))
          ORDER BY Agregado, IssueId) t;
END;
GO
