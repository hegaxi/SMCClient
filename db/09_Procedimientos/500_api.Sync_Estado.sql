/* Estado de la sincronización por fuente. El controlador lo consulta antes de ejecutar cualquier
   otro procedimiento: si DatosVigentes = 0 responde 503 y la interfaz muestra "Sincronizando...".
   Una fuente está vigente cuando TODAS sus entidades activas (no dependientes) terminaron bien
   dentro de cfg.Fuente.MaxAntiguedadMin. Segundo resultado: detalle por entidad. */
CREATE OR ALTER PROCEDURE api.Sync_Estado
    @Detalle bit = 1          -- 0 = solo el primer resultado (resumen por fuente)
AS
BEGIN
    SET NOCOUNT ON; SET ANSI_WARNINGS OFF;   -- MIN() sobre entidades sin ejecución no debe generar avisos
    DECLARE @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();
    DECLARE @maxIntentos tinyint = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'MaxIntentosDocumento') AS tinyint), 3);

    SELECT e.FuenteId, e.Entidad, e.Modo,
           (SELECT MAX(x.Fin) FROM sync.Ejecucion x WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad AND x.Estado IN ('ok', 'parcial')) AS UltimaOk,
           (SELECT TOP (1) x.Estado FROM sync.Ejecucion x WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad ORDER BY x.Inicio DESC) AS UltimoEstado
    INTO #e
    FROM cfg.EntidadSync e
    WHERE e.Activa = 1;

    SELECT f.Codigo AS Fuente,
           MIN(e.UltimaOk) AS UltimaSincronizacion,
           DATEDIFF(MINUTE, MIN(e.UltimaOk), @ahora) AS MinutosDesdeSincronizacion,
           CAST(CASE WHEN COUNT(CASE WHEN e.Modo <> 'dependiente' AND e.UltimaOk IS NULL THEN 1 END) = 0
                      AND DATEDIFF(MINUTE, MIN(CASE WHEN e.Modo <> 'dependiente' THEN e.UltimaOk END), @ahora) <= f.MaxAntiguedadMin
                     THEN 1 ELSE 0 END AS bit) AS DatosVigentes,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM sync.Candado c WHERE c.FuenteId = f.FuenteId AND c.ExpiraEn > @ahora AND c.Propietario IS NOT NULL)
                     THEN 1 ELSE 0 END AS bit) AS Sincronizando,
           (SELECT COUNT(*) FROM raw.Documento d WHERE d.FuenteId = f.FuenteId AND d.Procesado = 0 AND d.Intentos < @maxIntentos) AS DocumentosPendientes,
           (SELECT COUNT(*) FROM raw.Documento d WHERE d.FuenteId = f.FuenteId AND d.Procesado = 0 AND d.Intentos >= @maxIntentos) AS DocumentosEnCuarentena,
           (SELECT COUNT(*) FROM sync.Evento v WHERE v.FuenteId = f.FuenteId AND v.Atendido = 0 AND v.Nivel IN ('advertencia', 'error')) AS AvisosAbiertos
    FROM cfg.Fuente f
    LEFT JOIN #e e ON e.FuenteId = f.FuenteId
    WHERE f.Activa = 1
    GROUP BY f.FuenteId, f.Codigo, f.MaxAntiguedadMin;

    IF @Detalle = 0 RETURN;

    SELECT f.Codigo AS Fuente, e.Entidad, e.Modo, e.UltimaOk, e.UltimoEstado, m.Valor AS MarcaAgua
    FROM #e e
    JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId
    LEFT JOIN sync.MarcaAgua m ON m.FuenteId = e.FuenteId AND m.Entidad = e.Entidad
    ORDER BY f.Codigo, e.Entidad;
END;
GO
