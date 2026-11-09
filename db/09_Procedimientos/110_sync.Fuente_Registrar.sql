/* Da de alta una instancia de Jira con las entidades estándar. Idempotente: si ya existe, no
   modifica lo que el administrador haya cambiado; solo agrega las entidades que falten. */
CREATE OR ALTER PROCEDURE sync.Fuente_Registrar
    @Codigo   varchar(50),
    @Tipo     varchar(30) = 'jira-cloud',
    @UrlBase  nvarchar(300),
    @CloudId  varchar(64) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    IF NOT EXISTS (SELECT 1 FROM cfg.Fuente WHERE Codigo = @Codigo)
        INSERT cfg.Fuente (Codigo, Tipo, UrlBase, CloudId) VALUES (@Codigo, @Tipo, @UrlBase, @CloudId);

    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Codigo);

    INSERT cfg.EntidadSync (FuenteId, Entidad, Orden, Modo, FrecuenciaMin, Endpoint, TamanoLote, Procedimiento, ProcedimientoCierre, Parametros)
    SELECT @FuenteId, t.Entidad, t.Orden, t.Modo, t.FrecuenciaMin, t.Endpoint, t.TamanoLote, t.Procedimiento, t.Cierre, t.Parametros
    FROM (VALUES
        ('campo',             10, 'catalogo',    60, N'/rest/api/3/field',                                  500, N'sync.Procesar_Campos',              N'sync.Cerrar_Campos',    NULL),
        ('estado',            20, 'catalogo',    60, N'/rest/api/3/status',                                 500, N'sync.Procesar_Estados',             NULL,                     NULL),
        ('proyecto',          30, 'catalogo',    60, N'/rest/api/3/project/search',                         50,  N'sync.Procesar_Proyectos',           N'sync.Cerrar_Proyectos', NULL),
        ('issue',             40, 'incremental', 15, N'/rest/api/3/search/jql',                             100, N'sync.Procesar_Issues',              NULL,                     N'{"fields":"*all","jqlBase":""}'),
        ('changelog',         50, 'dependiente', 15, N'/rest/api/3/changelog/bulkfetch',                    100, N'sync.Procesar_Changelog',           NULL,                     NULL),
        ('worklog',           60, 'incremental', 15, N'/rest/api/3/worklog/updated',                        1000, N'sync.Procesar_Worklogs',           NULL,                     N'{"lista":"/rest/api/3/worklog/list"}'),
        ('worklog_eliminado', 70, 'incremental', 15, N'/rest/api/3/worklog/deleted',                        1000, N'sync.Procesar_WorklogsEliminados', NULL,                     NULL),
        ('sla',               80, 'dependiente', 15, N'/rest/servicedeskapi/request/{issueIdOrKey}/sla',    50,  N'sync.Procesar_Sla',                 NULL,                     N'{"soloTipoProyecto":"service_desk"}'),
        ('comentario',        90, 'dependiente', 15, N'/rest/api/2/issue/{issueIdOrKey}/comment',           50,  N'sync.Procesar_Comentarios',         NULL,                     NULL)
    ) t (Entidad, Orden, Modo, FrecuenciaMin, Endpoint, TamanoLote, Procedimiento, Cierre, Parametros)
    WHERE NOT EXISTS (SELECT 1 FROM cfg.EntidadSync e WHERE e.FuenteId = @FuenteId AND e.Entidad = t.Entidad);
    COMMIT;

    SELECT @FuenteId AS FuenteId;
END;
GO
