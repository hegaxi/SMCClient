/* Margen de tolerancia (5 a 10 080 minutos) para avisar que los datos de una fuente están atrasados: un tipo de dato
   está atrasado cuando lleva sin sincronizarse más que su frecuencia más este margen. */
CREATE OR ALTER PROCEDURE api.Sync_Antiguedad_Guardar
    @Fuente           varchar(50),
    @MaxAntiguedadMin int,
    @UsuarioActual    nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @f int, @antes int;
    SELECT @f = FuenteId, @antes = MaxAntiguedadMin FROM cfg.Fuente WHERE Codigo = @Fuente;
    IF @f IS NULL THROW 50404, 'La fuente no existe.', 1;
    IF @MaxAntiguedadMin IS NULL OR @MaxAntiguedadMin NOT BETWEEN 5 AND 10080 THROW 50400, 'El margen va de 5 a 10 080 minutos.', 1;
    UPDATE cfg.Fuente SET MaxAntiguedadMin = @MaxAntiguedadMin WHERE FuenteId = @f;
    DECLARE @a nvarchar(20) = CAST(@antes AS nvarchar(20)), @d nvarchar(20) = CAST(@MaxAntiguedadMin AS nvarchar(20));
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'sync.antiguedad', @Objeto = @Fuente, @Antes = @a, @Despues = @d;
    EXEC api.Sync_Frecuencias_Listar;
END;
GO
