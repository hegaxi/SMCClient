/* Estimado vs. real: estimación original de Jira contra las horas que REGISTRARON LAS PERSONAS (las automáticas de
   Automation for Jira no son esfuerzo), con todo el árbol de cada issue (una tarea con sus subtareas; una épica con
   sus tareas y subtareas). También mide la captura: cuántos issues aún no tienen estimación.
   Por omisión compara TAREAS e historias: sumar épicas y tareas a la vez contaba todo dos veces (la épica ya incluye a
   sus tareas). La estimación del árbol no suma la del padre y la de sus subtareas (ver sync.Resumen_Recalcular).
   Situación de cada issue: Excedida (registró más de lo estimado), En riesgo (abierto y lo registrado más lo restante
   ya supera lo estimado: HorasProyectadas), Dentro de lo estimado (terminado), En curso o Sin estimación.
   1) Resumen: issues, con y sin estimación, horas estimadas y registradas (de los estimados), desviación, % consumido
      y cuántos se excedieron.
   2) Detalle en árbol: Total → proyecto → épica (o "(Sin épica)") → tarea / historia → subtarea, cada fila con su
      estimado, registrado, desviación, % consumido y situación; entre hermanos, de la mayor desviación a la menor (los
      sin estimación al final). Las tareas son las del filtro (proyecto, épica, sprint, responsable, solo excedidas).
      Una épica muestra su árbol completo (incluye lo registrado en la propia épica) si no se filtró por sprint,
      responsable ni excedidas; si se filtró, la suma de sus tareas del filtro. */
CREATE OR ALTER PROCEDURE api.Estimacion_VsReal
    @Proyecto      varchar(50) = NULL,
    @Epica         varchar(50) = NULL,       -- clave de la épica
    @Sprint        nvarchar(255) = NULL,     -- parte del nombre del sprint
    @Responsable   nvarchar(255) = NULL,     -- parte del nombre
    @Nivel         varchar(10) = 'tarea',    -- tarea (tareas e historias) | epica
    @SoloExcedidas bit = 0,
    @Detalle       bit = 1                   -- 0 = solo el resumen
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nivel = ISNULL(NULLIF(@Nivel, ''), 'tarea');
    IF @Nivel NOT IN ('tarea', 'epica') THROW 50400, 'Nivel debe ser tarea o epica.', 1;

    SELECT i.Clave, i.Resumen, i.TipoIssue, i.Estado, i.CategoriaEstado, i.Responsable, i.EpicaClave AS Epica,
           i.HorasEstimadasArbol AS HorasEstimadas,
           ISNULL(i.HorasRegistradasArbol, 0) AS HorasRegistradas,
           CAST(i.EstimacionRestanteSeg / 3600.0 AS decimal(12,2)) AS HorasRestantes
    INTO #i
    FROM rpt.vIssue i
    WHERE i.NivelJerarquia >= 0   -- las subtareas cuentan dentro de su tarea
      AND ((@Nivel = 'epica' AND i.NivelJerarquia >= 1) OR (@Nivel = 'tarea' AND i.NivelJerarquia = 0))
      AND i.TipoProyecto = 'software'
      AND (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto)
      AND (@Epica IS NULL OR i.EpicaClave = @Epica)
      AND (@Responsable IS NULL OR CHARINDEX(@Responsable, i.Responsable) > 0)
      AND (@Sprint IS NULL OR EXISTS (SELECT 1 FROM ops.IssueSprint x JOIN ops.Sprint s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
                                      WHERE x.IssueSk = i.IssueSk AND CHARINDEX(@Sprint, s.Nombre) > 0))
    OPTION (RECOMPILE);

    SELECT COUNT(*) AS Issues,
           SUM(CASE WHEN HorasEstimadas IS NOT NULL THEN 1 ELSE 0 END) AS ConEstimacion,
           SUM(CASE WHEN HorasEstimadas IS NULL THEN 1 ELSE 0 END) AS SinEstimacion,
           CAST(100.0 * SUM(CASE WHEN HorasEstimadas IS NOT NULL THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS decimal(5,1)) AS PorcentajeConEstimacion,
           SUM(HorasEstimadas) AS HorasEstimadas,
           SUM(CASE WHEN HorasEstimadas IS NOT NULL THEN HorasRegistradas END) AS HorasRegistradasEstimados,
           CAST(SUM(CASE WHEN HorasEstimadas IS NOT NULL THEN HorasRegistradas END) - SUM(HorasEstimadas) AS decimal(12,2)) AS DesviacionHoras,
           CAST(100.0 * SUM(CASE WHEN HorasEstimadas IS NOT NULL THEN HorasRegistradas END) / NULLIF(SUM(HorasEstimadas), 0) AS decimal(9,1)) AS PorcentajeConsumo,
           SUM(CASE WHEN HorasRegistradas > HorasEstimadas THEN 1 ELSE 0 END) AS Excedidas,
           SUM(CASE WHEN HorasRegistradas <= HorasEstimadas AND CategoriaEstado <> 'done'
                     AND HorasRegistradas + ISNULL(HorasRestantes, 0) > HorasEstimadas THEN 1 ELSE 0 END) AS EnRiesgo
    FROM #i;

    IF @Detalle = 0 RETURN;

    /* ===== Detalle en árbol ===== */
    -- Tareas / historias del filtro (siempre tareas: las épicas son sus agrupadores).
    SELECT i.FuenteId, i.IssueId, i.Clave, i.Resumen, i.TipoIssue, i.Estado, i.CategoriaEstado, i.Responsable,
           i.ProyectoClave, i.ProyectoNombre, i.EpicaIssueId, i.EpicaClave,
           i.HorasEstimadasArbol AS Est, ISNULL(i.HorasRegistradasArbol, 0) AS Reg,
           CAST(i.EstimacionRestanteSeg / 3600.0 AS decimal(12,2)) AS Rest
    INTO #t
    FROM rpt.vIssue i
    WHERE i.NivelJerarquia = 0 AND i.TipoProyecto = 'software'
      AND (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto)
      AND (@Epica IS NULL OR i.EpicaClave = @Epica)
      AND (@Responsable IS NULL OR CHARINDEX(@Responsable, i.Responsable) > 0)
      AND (@Sprint IS NULL OR EXISTS (SELECT 1 FROM ops.IssueSprint x JOIN ops.Sprint s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId
                                      WHERE x.IssueSk = i.IssueSk AND CHARINDEX(@Sprint, s.Nombre) > 0))
      AND (@SoloExcedidas = 0 OR ISNULL(i.HorasRegistradasArbol, 0) > i.HorasEstimadasArbol)
    OPTION (RECOMPILE);

    DECLARE @completa bit = CASE WHEN @Sprint IS NULL AND @Responsable IS NULL AND @SoloExcedidas = 0 THEN 1 ELSE 0 END;

    CREATE TABLE #nodo (
        Nodo nvarchar(80) NOT NULL PRIMARY KEY, PadreNodo nvarchar(80) NULL, Nivel int NOT NULL, Clave varchar(50) NULL,
        Elemento nvarchar(400) NULL, Tipo nvarchar(255) NULL, Estado nvarchar(255) NULL, Responsable nvarchar(255) NULL,
        Terminado bit NULL, Est decimal(12,2) NULL, Reg decimal(12,2) NULL, Rest decimal(12,2) NULL, SinEst int NULL, Tareas int NULL);

    -- Subtareas de las tareas del filtro
    INSERT #nodo
    SELECT s.Clave, t.Clave, 4, s.Clave, s.Resumen, s.TipoIssue, s.Estado, s.Responsable,
           CASE WHEN s.CategoriaEstado = 'done' THEN 1 ELSE 0 END, s.HorasEstimadasArbol, ISNULL(s.HorasRegistradasArbol, 0),
           CAST(s.EstimacionRestanteSeg / 3600.0 AS decimal(12,2)), NULL, NULL
    FROM #t t JOIN rpt.vIssue s ON s.FuenteId = t.FuenteId AND s.PadreId = t.IssueId AND s.NivelJerarquia < 0;

    -- Tareas
    INSERT #nodo
    SELECT t.Clave, CASE WHEN t.EpicaClave IS NOT NULL THEN CAST(t.EpicaClave AS nvarchar(80)) ELSE N'S|' + t.ProyectoClave END, 3,
           t.Clave, t.Resumen, t.TipoIssue, t.Estado, t.Responsable, CASE WHEN t.CategoriaEstado = 'done' THEN 1 ELSE 0 END,
           t.Est, t.Reg, t.Rest, CASE WHEN t.Est IS NULL THEN 1 ELSE 0 END, 1
    FROM #t t;

    -- Épicas: su árbol completo, o la suma de sus tareas del filtro.
    INSERT #nodo
    SELECT e.Clave, N'P|' + MIN(t.ProyectoClave), 2, e.Clave, e.Resumen, e.TipoIssue, e.Estado, e.Responsable,
           CASE WHEN SUM(CASE WHEN t.CategoriaEstado <> 'done' THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
           CASE WHEN @completa = 1 THEN MAX(e.HorasEstimadasArbol) ELSE SUM(t.Est) END,
           CASE WHEN @completa = 1 THEN MAX(ISNULL(e.HorasRegistradasArbol, 0)) ELSE SUM(t.Reg) END,
           SUM(CASE WHEN t.CategoriaEstado <> 'done' THEN t.Rest END),
           SUM(CASE WHEN t.Est IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM #t t JOIN rpt.vIssue e ON e.FuenteId = t.FuenteId AND e.IssueId = t.EpicaIssueId
    GROUP BY e.Clave, e.Resumen, e.TipoIssue, e.Estado, e.Responsable;

    -- "(Sin épica)" de cada proyecto
    INSERT #nodo
    SELECT N'S|' + t.ProyectoClave, N'P|' + t.ProyectoClave, 2, NULL, N'(Sin épica)', N'Agrupador', NULL, NULL,
           CASE WHEN SUM(CASE WHEN t.CategoriaEstado <> 'done' THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
           SUM(t.Est), SUM(t.Reg), SUM(CASE WHEN t.CategoriaEstado <> 'done' THEN t.Rest END),
           SUM(CASE WHEN t.Est IS NULL THEN 1 ELSE 0 END), COUNT(*)
    FROM #t t WHERE t.EpicaClave IS NULL
    GROUP BY t.ProyectoClave;

    -- Proyectos (suma de sus épicas y "(Sin épica)") y total
    INSERT #nodo
    SELECT N'P|' + t.ProyectoClave, N'#total', 1, NULL, CAST(t.ProyectoClave + N' · ' + MAX(t.ProyectoNombre) AS nvarchar(400)), N'Proyecto', NULL, NULL,
           MIN(CAST(n.Terminado AS int)), SUM(n.Est), SUM(n.Reg), SUM(n.Rest), SUM(n.SinEst), SUM(n.Tareas)
    FROM #nodo n JOIN (SELECT DISTINCT ProyectoClave, ProyectoNombre FROM #t) t ON n.PadreNodo = N'P|' + t.ProyectoClave
    WHERE n.Nivel = 2
    GROUP BY t.ProyectoClave;
    INSERT #nodo
    SELECT N'#total', NULL, 0, NULL, N'Total', NULL, NULL, NULL, MIN(CAST(Terminado AS int)), SUM(Est), SUM(Reg), SUM(Rest), SUM(SinEst), SUM(Tareas)
    FROM #nodo WHERE Nivel = 1 HAVING COUNT(*) > 0;

    -- Orden entre hermanos: mayor desviación primero, los sin estimación al final.
    SELECT Nodo, PadreNodo,
           RIGHT('00000' + CAST(ROW_NUMBER() OVER (PARTITION BY PadreNodo
                 ORDER BY CASE WHEN Est IS NULL THEN 1 ELSE 0 END, Reg - Est DESC, Clave, Nodo) AS varchar(6)), 6) AS Pos
    INTO #pos FROM #nodo;
    WITH ruta AS (
        SELECT Nodo, CAST('' AS varchar(400)) AS Ruta FROM #pos WHERE PadreNodo IS NULL
        UNION ALL
        SELECT p.Nodo, CAST(r.Ruta + '/' + p.Pos AS varchar(400)) FROM ruta r JOIN #pos p ON p.PadreNodo = r.Nodo
    )
    SELECT n.Nodo, n.PadreNodo, n.Nivel,
           CASE n.Nivel WHEN 0 THEN N'Total' WHEN 1 THEN N'Proyecto' WHEN 2 THEN N'Épica' WHEN 3 THEN N'Tarea' ELSE N'Subtarea' END AS NivelNombre,
           n.Clave, n.Elemento, n.Tipo, n.Estado, n.Responsable,
           n.Est AS HorasEstimadas, n.Reg AS HorasRegistradas, n.Rest AS HorasRestantes,
           CAST(CASE WHEN n.Terminado = 0 THEN n.Reg + ISNULL(n.Rest, 0) END AS decimal(12,2)) AS HorasProyectadas,
           CAST(n.Reg - n.Est AS decimal(12,2)) AS DesviacionHoras,
           CAST(100.0 * n.Reg / NULLIF(n.Est, 0) AS decimal(9,1)) AS PorcentajeConsumo,
           CASE WHEN n.Est IS NULL THEN N'Sin estimación'
                WHEN n.Reg > n.Est THEN N'Excedida'
                WHEN n.Terminado = 0 AND n.Reg + ISNULL(n.Rest, 0) > n.Est THEN N'En riesgo'
                WHEN n.Terminado = 1 THEN N'Dentro de lo estimado'
                ELSE N'En curso' END AS Situacion,
           n.Tareas, n.SinEst AS TareasSinEstimacion
    FROM #nodo n JOIN ruta r ON r.Nodo = n.Nodo
    ORDER BY r.Ruta
    OPTION (MAXRECURSION 10);
END;
GO
