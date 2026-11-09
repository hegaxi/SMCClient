/* Estimado vs. real: estimación original de Jira contra las horas que REGISTRARON LAS PERSONAS (las automáticas de
   Automation for Jira no son esfuerzo), con todo el árbol de cada issue (una tarea con sus subtareas; una épica con
   sus tareas y subtareas). También mide la captura: cuántos issues aún no tienen estimación.
   1) Resumen: issues, con y sin estimación, horas estimadas y registradas (de los estimados), desviación, % consumido
      y cuántos se excedieron.
   2) Detalle por issue, de la mayor desviación a la menor (los sin estimación al final). */
CREATE OR ALTER PROCEDURE api.Estimacion_VsReal
    @Proyecto      varchar(50) = NULL,
    @Epica         varchar(50) = NULL,       -- clave de la épica
    @Sprint        nvarchar(255) = NULL,     -- parte del nombre del sprint
    @Responsable   nvarchar(255) = NULL,     -- parte del nombre
    @Nivel         varchar(10) = NULL,       -- tarea (tareas e historias) | epica | NULL = ambos
    @SoloExcedidas bit = 0,
    @Detalle       bit = 1                   -- 0 = solo el resumen
AS
BEGIN
    SET NOCOUNT ON;
    IF @Nivel IS NOT NULL AND @Nivel NOT IN ('tarea', 'epica') THROW 50400, 'Nivel debe ser tarea o epica.', 1;

    SELECT i.Clave, i.Resumen, i.TipoIssue, i.Estado, i.CategoriaEstado, i.Responsable, i.EpicaClave AS Epica,
           i.HorasEstimadasArbol AS HorasEstimadas,
           ISNULL(i.HorasRegistradasArbol, 0) AS HorasRegistradas,
           CAST(i.EstimacionRestanteSeg / 3600.0 AS decimal(12,2)) AS HorasRestantes
    INTO #i
    FROM rpt.vIssue i
    WHERE i.NivelJerarquia >= 0   -- las subtareas cuentan dentro de su tarea
      AND (@Nivel IS NULL OR (@Nivel = 'epica' AND i.NivelJerarquia >= 1) OR (@Nivel = 'tarea' AND i.NivelJerarquia = 0))
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
           SUM(CASE WHEN HorasRegistradas > HorasEstimadas THEN 1 ELSE 0 END) AS Excedidas
    FROM #i;

    IF @Detalle = 0 RETURN;

    SELECT Clave, Resumen, TipoIssue, Estado, Responsable, Epica, HorasEstimadas, HorasRegistradas, HorasRestantes,
           CAST(HorasRegistradas - HorasEstimadas AS decimal(12,2)) AS DesviacionHoras,
           CAST(100.0 * HorasRegistradas / NULLIF(HorasEstimadas, 0) AS decimal(9,1)) AS PorcentajeConsumo,
           CASE WHEN HorasEstimadas IS NULL THEN N'Sin estimación'
                WHEN HorasRegistradas > HorasEstimadas THEN N'Excedida'
                WHEN CategoriaEstado = 'done' THEN N'Dentro de lo estimado'
                ELSE N'En curso' END AS Situacion
    FROM #i
    WHERE @SoloExcedidas = 0 OR HorasRegistradas > HorasEstimadas
    ORDER BY CASE WHEN HorasEstimadas IS NULL THEN 1 ELSE 0 END, HorasRegistradas - HorasEstimadas DESC, Clave;
END;
GO
