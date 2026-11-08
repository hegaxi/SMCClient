/* Al terminar un catálogo COMPLETO de campos: marca como baja los que ya no vinieron y
   vuelve a resolver los roles. Protección: si el catálogo trae menos del UmbralBajaCatalogoPct
   de los campos activos (respuesta incompleta, permisos, error de Jira) no da de baja nada. */
CREATE OR ALTER PROCEDURE sync.Cerrar_Campos
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @esCatalogo bit = CASE WHEN EXISTS (SELECT 1 FROM sync.Ejecucion WHERE EjecucionId = @EjecucionId AND Entidad = 'campo' AND Modo = 'catalogo') THEN 1 ELSE 0 END;

    IF @esCatalogo = 1
    BEGIN
        DECLARE @umbral int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'UmbralBajaCatalogoPct') AS int), 50);
        DECLARE @vistos int = (SELECT COUNT(*) FROM raw.Documento WHERE FuenteId = @FuenteId AND Entidad = 'campo' AND LoteId = @EjecucionId);
        DECLARE @activos int = (SELECT COUNT(*) FROM meta.CampoJira WHERE FuenteId = @FuenteId AND Activo = 1);
        DECLARE @msg nvarchar(1000), @datos nvarchar(max);

        IF @activos > 0 AND @vistos * 100 < @activos * @umbral
        BEGIN
            SET @msg = CONCAT(N'El catálogo de campos llegó con ', @vistos, N' de ', @activos, N' campos activos. No se dio de baja ninguno (posible respuesta incompleta).');
            EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'campo.catalogo_incompleto', @msg;
        END
        ELSE
        BEGIN
            SELECT m.CampoId, m.Nombre INTO #bajas
            FROM meta.CampoJira m
            WHERE m.FuenteId = @FuenteId AND m.Activo = 1
              AND NOT EXISTS (SELECT 1 FROM raw.Documento d WHERE d.FuenteId = @FuenteId AND d.Entidad = 'campo'
                                AND d.LoteId = @EjecucionId AND d.IdExterno = m.CampoId);

            IF EXISTS (SELECT 1 FROM #bajas)
            BEGIN
                BEGIN TRAN;
                UPDATE m SET Activo = 0, FechaBaja = SYSDATETIMEOFFSET()
                FROM meta.CampoJira m JOIN #bajas b ON m.FuenteId = @FuenteId AND m.CampoId = b.CampoId;
                INSERT meta.CampoJiraCambio (FuenteId, CampoId, TipoCambio, ValorAnterior, EjecucionId)
                SELECT @FuenteId, CampoId, 'baja', Nombre, @EjecucionId FROM #bajas;
                COMMIT;

                -- Los valores históricos en ops.IssueCampoValor se conservan.
                SET @datos = (SELECT b.CampoId, b.Nombre, mc.Rol FROM #bajas b
                              LEFT JOIN cfg.MapeoCampo mc ON mc.FuenteId = @FuenteId AND mc.CampoId = b.CampoId FOR JSON PATH);
                SET @msg = CONCAT(N'Se eliminaron ', (SELECT COUNT(*) FROM #bajas), N' campo(s) en Jira. Sus valores históricos se conservan.');
                EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'campo.baja', @msg, @datos;
            END;
        END;
    END;

    EXEC sync.ResolverMapeos @FuenteId = @FuenteId, @EjecucionId = @EjecucionId;
END;
GO
