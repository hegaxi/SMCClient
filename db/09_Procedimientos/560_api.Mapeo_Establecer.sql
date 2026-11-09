/* Asigna manualmente el campo de Jira de un rol (p. ej. cuando hay dos campos "Story Points").
   @CampoId = NULL devuelve el rol a resolución automática. Reprocesa los issues desde raw. */
CREATE OR ALTER PROCEDURE api.Mapeo_Establecer
    @Fuente  varchar(50),
    @Rol     varchar(50),
    @CampoId varchar(100) = NULL,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50404, 'La fuente no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM cfg.RolCampo WHERE Rol = @Rol) THROW 50404, 'El rol no existe.', 1;
    IF @CampoId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM meta.CampoJira WHERE FuenteId = @FuenteId AND CampoId = @CampoId AND Activo = 1)
        THROW 50112, 'El campo no existe o está inactivo en el catálogo.', 1;

    DECLARE @antes nvarchar(max) = (SELECT CampoId, Origen FROM cfg.MapeoCampo WHERE FuenteId = @FuenteId AND Rol = @Rol FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @objeto nvarchar(200) = CONCAT(@Fuente, N'/', @Rol);
    DECLARE @despues nvarchar(max) = (SELECT @CampoId AS CampoId, CASE WHEN @CampoId IS NULL THEN 'auto' ELSE 'manual' END AS Origen FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    BEGIN TRAN;
    IF @CampoId IS NULL
        UPDATE cfg.MapeoCampo SET Origen = 'auto', CampoId = NULL, FechaResolucion = SYSDATETIMEOFFSET() WHERE FuenteId = @FuenteId AND Rol = @Rol;
    ELSE
    BEGIN
        UPDATE cfg.MapeoCampo SET Origen = 'manual', CampoId = @CampoId, FechaResolucion = SYSDATETIMEOFFSET() WHERE FuenteId = @FuenteId AND Rol = @Rol;
        IF @@ROWCOUNT = 0 INSERT cfg.MapeoCampo (FuenteId, Rol, CampoId, Origen) VALUES (@FuenteId, @Rol, @CampoId, 'manual');
    END;
    UPDATE raw.Documento SET Procesado = 0, Intentos = 0, ErrorProceso = NULL WHERE FuenteId = @FuenteId AND Entidad = 'issue';
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'mapeo.establecer', @Objeto = @objeto, @Antes = @antes, @Despues = @despues;
    COMMIT;

    EXEC sync.ResolverMapeos @FuenteId = @FuenteId;
    EXEC api.Mapeos_Listar @Fuente = @Fuente;
END;
GO
