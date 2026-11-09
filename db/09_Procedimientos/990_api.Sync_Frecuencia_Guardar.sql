/* Cada cuántos minutos se sincroniza un tipo de dato de una fuente (1 a 10 080 = una semana). El worker lo toma en su
   siguiente ciclo. El aviso de datos atrasados se ajusta solo: frecuencia + margen de la fuente. */
CREATE OR ALTER PROCEDURE api.Sync_Frecuencia_Guardar
    @Fuente        varchar(50),
    @Entidad       varchar(40),
    @FrecuenciaMin int,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @f IS NULL THROW 50404, 'La fuente no existe.', 1;
    DECLARE @antes int = (SELECT FrecuenciaMin FROM cfg.EntidadSync WHERE FuenteId = @f AND Entidad = @Entidad);
    IF @antes IS NULL THROW 50404, 'Ese tipo de dato no se sincroniza en la fuente.', 1;
    IF @FrecuenciaMin IS NULL OR @FrecuenciaMin NOT BETWEEN 1 AND 10080 THROW 50400, 'La frecuencia va de 1 a 10 080 minutos.', 1;
    UPDATE cfg.EntidadSync SET FrecuenciaMin = @FrecuenciaMin WHERE FuenteId = @f AND Entidad = @Entidad;
    DECLARE @obj nvarchar(200) = CONCAT(@Fuente, N'/', @Entidad), @a nvarchar(20) = CAST(@antes AS nvarchar(20)), @d nvarchar(20) = CAST(@FrecuenciaMin AS nvarchar(20));
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'sync.frecuencia', @Objeto = @obj, @Antes = @a, @Despues = @d;
    EXEC api.Sync_Frecuencias_Listar;
END;
GO
