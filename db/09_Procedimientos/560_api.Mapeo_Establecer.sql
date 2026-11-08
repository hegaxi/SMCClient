/* Asigna manualmente el campo de Jira de un rol (p. ej. cuando hay dos campos "Story Points").
   @CampoId = NULL devuelve el rol a resolución automática. Reprocesa los issues desde raw. */
CREATE OR ALTER PROCEDURE api.Mapeo_Establecer
    @Fuente  varchar(50),
    @Rol     varchar(50),
    @CampoId varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50404, 'La fuente no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM cfg.RolCampo WHERE Rol = @Rol) THROW 50404, 'El rol no existe.', 1;
    IF @CampoId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM meta.CampoJira WHERE FuenteId = @FuenteId AND CampoId = @CampoId AND Activo = 1)
        THROW 50112, 'El campo no existe o está inactivo en el catálogo.', 1;

    BEGIN TRAN;
    IF @CampoId IS NULL
        UPDATE cfg.MapeoCampo SET Origen = 'auto', CampoId = NULL, FechaResolucion = SYSDATETIMEOFFSET() WHERE FuenteId = @FuenteId AND Rol = @Rol;
    ELSE
    BEGIN
        UPDATE cfg.MapeoCampo SET Origen = 'manual', CampoId = @CampoId, FechaResolucion = SYSDATETIMEOFFSET() WHERE FuenteId = @FuenteId AND Rol = @Rol;
        IF @@ROWCOUNT = 0 INSERT cfg.MapeoCampo (FuenteId, Rol, CampoId, Origen) VALUES (@FuenteId, @Rol, @CampoId, 'manual');
    END;
    UPDATE raw.Documento SET Procesado = 0, Intentos = 0, ErrorProceso = NULL WHERE FuenteId = @FuenteId AND Entidad = 'issue';
    COMMIT;

    EXEC sync.ResolverMapeos @FuenteId = @FuenteId;
    EXEC api.Mapeos_Listar @Fuente = @Fuente;
END;
GO
