/* Excluye (o vuelve a incluir) un proyecto de la sincronización y de los reportes. */
CREATE OR ALTER PROCEDURE sync.Proyecto_Excluir
    @Fuente  varchar(50),
    @Clave   varchar(50),
    @Motivo  nvarchar(200) = NULL,
    @Excluir bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50070, 'La fuente no existe.', 1;
    IF @Excluir = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM cfg.ProyectoExcluido WHERE FuenteId = @FuenteId AND ProyectoClave = @Clave)
            INSERT cfg.ProyectoExcluido (FuenteId, ProyectoClave, Motivo) VALUES (@FuenteId, @Clave, @Motivo);
    END
    ELSE
    BEGIN
        DELETE cfg.ProyectoExcluido WHERE FuenteId = @FuenteId AND ProyectoClave = @Clave;
        -- Al volver a incluirlo, sus issues se traen con un backfill del proyecto.
        INSERT sync.Solicitud (FuenteId, Entidad, Modo, Parametros, SolicitadoPor)
        VALUES (@FuenteId, 'issue', 'backfill', (SELECT @Clave AS proyecto FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), N'sistema:proyecto.incluido');
    END;
END;
GO
