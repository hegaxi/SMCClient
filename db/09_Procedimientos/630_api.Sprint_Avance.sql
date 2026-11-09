/* Avance por sprint, con el estado de cada issue AL INICIO y AL CIERRE del sprint (historial de estados, ver
   rpt.fn_CategoriaEstadoEn), no el de hoy: un issue terminado tres sprints después no cuenta como terminado en los
   anteriores. Issues = sin contar subtareas.
   - Comprometidos: estaban en el sprint al empezar (no se agregaron después) y no estaban ya terminados.
   - Agregados: entraron al sprint después de su inicio (historial del campo Sprint, con 1 h de gracia); lo que llega
     arrastrado del sprint anterior al cerrarlo no cuenta como agregado.
   - TerminadosAlCierre: terminados al cerrarse el sprint (o hoy, si sigue abierto); TerminadosComprometidos: de los
     comprometidos. PorcentajeCumplimiento = TerminadosComprometidos / Comprometidos (lo prometido contra lo entregado).
   - Arrastrados: sin terminar al cierre y presentes en un sprint posterior del mismo tablero.
   - Horas: worklogs dentro de la VENTANA del sprint (de su inicio a su cierre, o hasta hoy si sigue activo, y nunca
     después del inicio del siguiente sprint del mismo tablero: así un worklog no cuenta en dos sprints que se traslapan),
     en los issues del sprint y sus subtareas, separadas las registradas por personas de las automáticas.
   - Estimación: la del árbol de cada issue (sin doble conteo, ver sync.Resumen_Recalcular).
   - Vencido = sigue activo después de su fecha de fin (hay que cerrarlo en Jira). */
CREATE OR ALTER PROCEDURE api.Sprint_Avance
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL    -- future | active | closed
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();

    SELECT s.FuenteId, s.SprintId, s.TableroId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado,
           CAST(CASE WHEN s.Estado = 'active' AND s.Fin < @ahora THEN 1 ELSE 0 END AS bit) AS Vencido,
           COALESCE(s.Completado, CASE WHEN s.Estado = 'active' AND @ahora > s.Fin THEN @ahora END, s.Fin) AS FinEfectivo,
           -- Momento del corte para "terminado al cierre": el cierre real, o ahora si sigue abierto.
           CASE WHEN s.Completado IS NOT NULL THEN s.Completado WHEN s.Estado = 'future' THEN s.Inicio ELSE @ahora END AS Corte,
           (SELECT MIN(n.Inicio) FROM ops.Sprint n
            WHERE n.FuenteId = s.FuenteId AND n.TableroId = s.TableroId AND n.SprintId <> s.SprintId AND n.Inicio > s.Inicio) AS InicioSiguiente
    INTO #s FROM ops.Sprint s WHERE @Estado IS NULL OR s.Estado = @Estado;
    ALTER TABLE #s ADD FinVentana datetimeoffset(3) NULL;
    UPDATE #s SET FinVentana = CASE WHEN InicioSiguiente IS NOT NULL AND InicioSiguiente < FinEfectivo THEN InicioSiguiente ELSE FinEfectivo END;

    SELECT x.FuenteId, x.SprintId, i.IssueSk, i.IssueId, i.ProyectoClave, i.StoryPoints, i.EsSubtarea, i.HorasEstimadasArbol,
           ini.Categoria AS CatInicio, fin.Categoria AS CatCierre,
           CAST(CASE WHEN EXISTS (
                SELECT 1 FROM ops.IssueCambio c
                WHERE c.IssueSk = i.IssueSk AND c.CampoId = (SELECT mc.CampoId FROM cfg.MapeoCampo mc WHERE mc.FuenteId = i.FuenteId AND mc.Rol = 'sprint')
                  AND c.Fecha > DATEADD(HOUR, 1, s.Inicio) AND c.Fecha < s.FinVentana
                  AND N',' + REPLACE(ISNULL(c.Hacia, N''), N' ', N'') + N',' LIKE N'%,' + CAST(s.SprintId AS nvarchar(20)) + N',%'
                  AND N',' + REPLACE(ISNULL(c.Desde, N''), N' ', N'') + N',' NOT LIKE N'%,' + CAST(s.SprintId AS nvarchar(20)) + N',%'
                  -- Un arrastre no es alcance nuevo: Jira mueve lo pendiente al cerrar el sprint anterior, que puede
                  -- ser después de que éste empezó. Se reconoce porque venía de un sprint que se cerró ese día.
                  AND NOT EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(c.Desde, N''), N',') d
                                  JOIN ops.Sprint p ON p.FuenteId = i.FuenteId AND p.SprintId = TRY_CAST(LTRIM(RTRIM(d.value)) AS bigint)
                                  WHERE p.Completado BETWEEN DATEADD(DAY, -1, c.Fecha) AND DATEADD(HOUR, 1, c.Fecha)))
                THEN 1 ELSE 0 END AS bit) AS Agregado,
           CAST(CASE WHEN s.Completado IS NOT NULL AND EXISTS (
                SELECT 1 FROM ops.IssueSprint y JOIN ops.Sprint n ON n.FuenteId = y.FuenteId AND n.SprintId = y.SprintId
                WHERE y.IssueSk = i.IssueSk AND n.TableroId = s.TableroId AND n.Inicio > s.Inicio)
                THEN 1 ELSE 0 END AS bit) AS EnSprintPosterior
    INTO #iss
    FROM ops.IssueSprint x
    JOIN #s s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
    JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
    OUTER APPLY rpt.fn_CategoriaEstadoEn(i.IssueSk, s.Inicio) ini
    OUTER APPLY rpt.fn_CategoriaEstadoEn(i.IssueSk, s.Corte) fin
    WHERE @Proyecto IS NULL OR i.ProyectoClave = @Proyecto;

    -- Issues cuyos worklogs cuentan para el sprint: los del sprint y sus subtareas.
    SELECT DISTINCT FuenteId, SprintId, IssueId INTO #m FROM (
        SELECT FuenteId, SprintId, IssueId FROM #iss
        UNION ALL
        SELECT st.FuenteId, i.SprintId, st.IssueId
        FROM #iss i JOIN ops.Issue st ON st.FuenteId = i.FuenteId AND st.PadreId = i.IssueId AND st.EsSubtarea = 1 AND st.Eliminado = 0
    ) u;
    CREATE CLUSTERED INDEX ix ON #m (FuenteId, IssueId, SprintId);

    SELECT m.FuenteId, m.SprintId,
           SUM(CASE WHEN COALESCE(w.EsAutomatico, CASE WHEN u.TipoCuenta = 'app' THEN 1 ELSE 0 END) = 0 THEN CAST(w.Segundos AS bigint) END) / 3600.0 AS Registradas,
           SUM(CASE WHEN COALESCE(w.EsAutomatico, CASE WHEN u.TipoCuenta = 'app' THEN 1 ELSE 0 END) = 1 THEN CAST(w.Segundos AS bigint) END) / 3600.0 AS Automaticas
    INTO #horas
    FROM #m m
    JOIN #s s ON s.FuenteId = m.FuenteId AND s.SprintId = m.SprintId
    JOIN ops.Worklog w WITH (FORCESEEK(IX_ops_Worklog_IssueDet(FuenteId, IssueId))) ON w.FuenteId = m.FuenteId AND w.IssueId = m.IssueId AND w.Eliminado = 0 AND ISNULL(w.EsCopia, 0) = 0 AND w.Inicio >= s.Inicio AND w.Inicio < s.FinVentana
    LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId
    GROUP BY m.FuenteId, m.SprintId;

    SELECT s.SprintId, MIN(iss.ProyectoClave) AS Proyecto, s.Nombre AS Sprint, s.Estado, s.Inicio, s.Fin, s.Completado, s.Vencido,
           SUM(CASE WHEN iss.EsSubtarea = 0 THEN 1 ELSE 0 END) AS Issues,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.Agregado = 0 AND ISNULL(iss.CatInicio, '') <> 'done' THEN 1 ELSE 0 END) AS Comprometidos,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.Agregado = 1 THEN 1 ELSE 0 END) AS Agregados,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.CatInicio = 'done' THEN 1 ELSE 0 END) AS YaTerminadosAlInicio,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.CatCierre = 'done' THEN 1 ELSE 0 END) AS TerminadosAlCierre,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.Agregado = 0 AND ISNULL(iss.CatInicio, '') <> 'done' AND iss.CatCierre = 'done' THEN 1 ELSE 0 END) AS TerminadosComprometidos,
           CAST(100.0 * SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.Agregado = 0 AND ISNULL(iss.CatInicio, '') <> 'done' AND iss.CatCierre = 'done' THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.Agregado = 0 AND ISNULL(iss.CatInicio, '') <> 'done' THEN 1 ELSE 0 END), 0) AS decimal(5,1)) AS PorcentajeCumplimiento,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND ISNULL(iss.CatCierre, '') <> 'done' AND iss.EnSprintPosterior = 1 THEN 1 ELSE 0 END) AS Arrastrados,
           SUM(iss.StoryPoints) AS StoryPoints,
           SUM(CASE WHEN iss.CatCierre = 'done' THEN iss.StoryPoints END) AS StoryPointsTerminados,
           CAST(MAX(h.Registradas) AS decimal(12,2)) AS HorasRegistradas,
           CAST(MAX(h.Automaticas) AS decimal(12,2)) AS HorasAutomaticas,
           SUM(CASE WHEN iss.EsSubtarea = 0 THEN iss.HorasEstimadasArbol END) AS HorasEstimadas,
           SUM(CASE WHEN iss.EsSubtarea = 0 AND iss.HorasEstimadasArbol IS NULL THEN 1 ELSE 0 END) AS IssuesSinEstimacion
    FROM #s s
    JOIN #iss iss ON iss.FuenteId = s.FuenteId AND iss.SprintId = s.SprintId
    LEFT JOIN #horas h ON h.FuenteId = s.FuenteId AND h.SprintId = s.SprintId
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado, s.Vencido
    ORDER BY s.Inicio DESC;
END;
GO
