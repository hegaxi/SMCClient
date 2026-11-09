/* Estado de la sincronización por fuente. El controlador lo consulta antes de ejecutar cualquier
   otro procedimiento: si DatosVigentes = 0 responde 503 y la interfaz muestra "Sincronizando...".
   DatosVigentes = la fuente ya completó su PRIMERA carga (todas sus entidades activas no dependientes terminaron
   bien al menos una vez). Después, si Jira o el worker fallan, la aplicación sigue funcionando con los datos que ya
   tiene: DatosAtrasados = 1 cuando algún tipo de dato lleva sin sincronizarse más que SU frecuencia más el margen
   cfg.Fuente.MaxAntiguedadMin (un catálogo que se pide cada hora no se considera atrasado a los 31 minutos), y la
   interfaz lo avisa sin bloquear. Segundo resultado: detalle por entidad. */
CREATE OR ALTER PROCEDURE api.Sync_Estado
    @Detalle       bit = 1,          -- 0 = solo el primer resultado (resumen por fuente)
    @UsuarioActual nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET ANSI_WARNINGS OFF;   -- MIN() sobre entidades sin ejecución no debe generar avisos
    DECLARE @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();
    DECLARE @maxIntentos tinyint = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'MaxIntentosDocumento') AS tinyint), 3);

    SELECT e.FuenteId, e.Entidad, e.Modo, e.FrecuenciaMin,
           (SELECT MAX(x.Fin) FROM sync.Ejecucion x WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad AND x.Estado IN ('ok', 'parcial')) AS UltimaOk,
           u.Estado AS UltimoEstado, u.Mensaje AS UltimoMensaje, u.Inicio AS UltimoIntento
    INTO #e
    FROM cfg.EntidadSync e
    OUTER APPLY (SELECT TOP (1) x.Estado, LEFT(x.Mensaje, 300) AS Mensaje, x.Inicio FROM sync.Ejecucion x
                 WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad ORDER BY x.EjecucionId DESC) u
    WHERE e.Activa = 1;

    SELECT f.Codigo AS Fuente,
           -- Las dependientes (historial, SLA) solo corren cuando hay issues pendientes: no cuentan para la antigüedad.
           MIN(CASE WHEN e.Modo <> 'dependiente' THEN e.UltimaOk END) AS UltimaSincronizacion,
           DATEDIFF(MINUTE, MIN(CASE WHEN e.Modo <> 'dependiente' THEN e.UltimaOk END), @ahora) AS MinutosDesdeSincronizacion,
           CAST(CASE WHEN COUNT(CASE WHEN e.Modo <> 'dependiente' THEN 1 END) > 0
                      AND COUNT(CASE WHEN e.Modo <> 'dependiente' AND e.UltimaOk IS NULL THEN 1 END) = 0
                     THEN 1 ELSE 0 END AS bit) AS DatosVigentes,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM sync.Candado c WHERE c.FuenteId = f.FuenteId AND c.ExpiraEn > @ahora AND c.Propietario IS NOT NULL)
                     THEN 1 ELSE 0 END AS bit) AS Sincronizando,
           (SELECT COUNT(*) FROM raw.Documento d WHERE d.FuenteId = f.FuenteId AND d.Procesado = 0 AND d.Intentos < @maxIntentos) AS DocumentosPendientes,
           (SELECT COUNT(*) FROM raw.Documento d WHERE d.FuenteId = f.FuenteId AND d.Procesado = 0 AND d.Intentos >= @maxIntentos) AS DocumentosEnCuarentena,
           (SELECT COUNT(*) FROM sync.Evento v WHERE v.FuenteId = f.FuenteId AND v.Atendido = 0 AND v.Nivel IN ('advertencia', 'error')) AS AvisosAbiertos,
           CAST(CASE WHEN COUNT(CASE WHEN e.Modo <> 'dependiente' AND DATEDIFF(MINUTE, e.UltimaOk, @ahora) > e.FrecuenciaMin + f.MaxAntiguedadMin THEN 1 END) > 0
                     THEN 1 ELSE 0 END AS bit) AS DatosAtrasados,
           f.MaxAntiguedadMin,
           (SELECT COUNT(*) FROM sync.IssuePendiente p WHERE p.FuenteId = f.FuenteId) AS IssuesPendientes
    FROM cfg.Fuente f
    LEFT JOIN #e e ON e.FuenteId = f.FuenteId
    WHERE f.Activa = 1
    GROUP BY f.FuenteId, f.Codigo, f.MaxAntiguedadMin;

    -- Los usuarios externos (clientes) solo ven el resumen: el detalle trae mensajes internos de la sincronización.
    IF @Detalle = 0 OR seg.fn_EsExterno((SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual)) = 1 RETURN;

    SELECT f.Codigo AS Fuente, e.Entidad, e.Modo, e.UltimaOk, e.UltimoEstado, e.UltimoIntento, e.UltimoMensaje, m.Valor AS MarcaAgua
    FROM #e e
    JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId
    LEFT JOIN sync.MarcaAgua m ON m.FuenteId = e.FuenteId AND m.Entidad = e.Entidad
    ORDER BY f.Codigo, (SELECT Orden FROM cfg.EntidadSync x WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad);
END;
GO
