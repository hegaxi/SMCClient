/* Integra el catálogo de campos (documentos de GET /rest/api/3/field) en meta.CampoJira y registra
   altas, renombres, cambios de tipo y reactivaciones. Las BAJAS se detectan en sync.Cerrar_Campos,
   cuando ya llegó el catálogo completo.
   Un campo nuevo (que no estaba en la primera carga) genera una solicitud de backfill: la
   sincronización incremental no ve los issues viejos que ya tenían valor en ese campo. */
CREATE OR ALTER PROCEDURE sync.Procesar_Campos
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();
    DECLARE @inicioEjecucion datetimeoffset(3) = ISNULL((SELECT Inicio FROM sync.Ejecucion WHERE EjecucionId = @EjecucionId), @ahora);
    -- Es primera carga si no hay campos registrados antes de que empezara esta ejecución.
    DECLARE @primeraCarga bit = CASE WHEN EXISTS (SELECT 1 FROM meta.CampoJira WHERE FuenteId = @FuenteId AND PrimeraVez < @inicioEjecucion) THEN 0 ELSE 1 END;

    SELECT j.CampoId, j.Nombre, ISNULL(j.EsCustom, 0) AS EsCustom, j.TipoSchema, j.ItemsSchema, j.TipoCustom, j.CampoSistema,
           HASHBYTES('SHA2_256', CONCAT(j.TipoSchema, N'|', j.ItemsSchema, N'|', j.TipoCustom)) AS HashTipo
    INTO #c
    FROM #lote l
    JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
    CROSS APPLY OPENJSON(d.Json) WITH (
        CampoId      varchar(100)  '$.id',
        Nombre       nvarchar(255) '$.name',
        EsCustom     bit           '$.custom',
        TipoSchema   varchar(100)  '$.schema.type',
        ItemsSchema  varchar(100)  '$.schema.items',
        TipoCustom   nvarchar(200) '$.schema.custom',
        CampoSistema varchar(100)  '$.schema.system'
    ) j
    WHERE j.CampoId IS NOT NULL;

    -- Cambios sobre campos existentes (se registran antes de actualizar).
    INSERT meta.CampoJiraCambio (FuenteId, CampoId, TipoCambio, ValorAnterior, ValorNuevo, EjecucionId)
    SELECT @FuenteId, c.CampoId, 'renombre', m.Nombre, c.Nombre, @EjecucionId
    FROM #c c JOIN meta.CampoJira m ON m.FuenteId = @FuenteId AND m.CampoId = c.CampoId
    WHERE m.Nombre <> c.Nombre COLLATE Latin1_General_CS_AS
    UNION ALL
    SELECT @FuenteId, c.CampoId, 'cambio_tipo',
           CONCAT(m.TipoSchema, N'/', m.ItemsSchema, N'/', m.TipoCustom), CONCAT(c.TipoSchema, N'/', c.ItemsSchema, N'/', c.TipoCustom), @EjecucionId
    FROM #c c JOIN meta.CampoJira m ON m.FuenteId = @FuenteId AND m.CampoId = c.CampoId
    WHERE m.HashDefinicion <> c.HashTipo
    UNION ALL
    SELECT @FuenteId, c.CampoId, 'reactivado', NULL, c.Nombre, @EjecucionId
    FROM #c c JOIN meta.CampoJira m ON m.FuenteId = @FuenteId AND m.CampoId = c.CampoId
    WHERE m.Activo = 0;

    DECLARE @msg nvarchar(1000), @datos nvarchar(max);
    IF EXISTS (SELECT 1 FROM #c c JOIN meta.CampoJira m ON m.FuenteId = @FuenteId AND m.CampoId = c.CampoId WHERE m.HashDefinicion <> c.HashTipo)
    BEGIN
        SET @datos = (SELECT c.CampoId, c.Nombre, c.TipoSchema, c.TipoCustom FROM #c c JOIN meta.CampoJira m ON m.FuenteId = @FuenteId AND m.CampoId = c.CampoId
                      WHERE m.HashDefinicion <> c.HashTipo FOR JSON PATH);
        EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'campo.cambio_tipo',
             N'Cambió el tipo de uno o más campos en Jira. Sus valores nuevos se guardan con el tipo nuevo; revise reportes que los usen.', @datos;
    END;

    UPDATE m SET Nombre = c.Nombre, EsCustom = c.EsCustom, TipoSchema = c.TipoSchema, ItemsSchema = c.ItemsSchema,
                 TipoCustom = c.TipoCustom, CampoSistema = c.CampoSistema, HashDefinicion = c.HashTipo,
                 Activo = 1, FechaBaja = NULL, UltimaVez = @ahora
    FROM meta.CampoJira m JOIN #c c ON m.FuenteId = @FuenteId AND m.CampoId = c.CampoId;

    -- Altas.
    SELECT c.* INTO #nuevos FROM #c c
    WHERE NOT EXISTS (SELECT 1 FROM meta.CampoJira m WHERE m.FuenteId = @FuenteId AND m.CampoId = c.CampoId);

    INSERT meta.CampoJira (FuenteId, CampoId, Nombre, EsCustom, TipoSchema, ItemsSchema, TipoCustom, CampoSistema, GuardarValor, PrimeraVez, UltimaVez, HashDefinicion)
    SELECT @FuenteId, n.CampoId, n.Nombre, n.EsCustom, n.TipoSchema, n.ItemsSchema, n.TipoCustom, n.CampoSistema,
           CASE
               WHEN n.EsCustom = 1 AND n.TipoCustom IN (N'com.atlassian.servicedesk:sd-sla-field',     -- se integra en ops.IssueSla
                                                        N'com.pyxis.greenhopper.jira:gh-lexo-rank')   -- orden interno del tablero
                    THEN 0
               WHEN n.EsCustom = 1 THEN 1
               WHEN n.CampoId IN ('labels', 'components', 'fixVersions', 'versions') THEN 1
               ELSE 0     -- los demás campos del sistema ya son columnas de ops.Issue o no aportan
           END,
           @ahora, @ahora, n.HashTipo
    FROM #nuevos n;

    INSERT meta.CampoJiraCambio (FuenteId, CampoId, TipoCambio, ValorNuevo, EjecucionId)
    SELECT @FuenteId, CampoId, 'alta', Nombre, @EjecucionId FROM #nuevos;

    IF @primeraCarga = 0 AND EXISTS (SELECT 1 FROM #nuevos)
    BEGIN
        SET @datos = (SELECT CampoId, Nombre, TipoSchema, TipoCustom FROM #nuevos FOR JSON PATH);
        SET @msg = CONCAT(N'Se detectaron ', (SELECT COUNT(*) FROM #nuevos), N' campo(s) nuevo(s) en Jira. Se programó su backfill.');
        EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'info', 'campo.alta', @msg, @datos;

        INSERT sync.Solicitud (FuenteId, Entidad, Modo, Parametros, SolicitadoPor)
        SELECT @FuenteId, 'issue', 'backfill', (SELECT n.CampoId AS campoId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), N'sistema:campo.alta'
        FROM #nuevos n
        WHERE n.EsCustom = 1;
    END;
END;
GO
