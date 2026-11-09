/* Avance de épicas: sus tareas (hijos directos que no son subtareas), cuántas están terminadas, story points,
   estimación y horas de toda la épica (la épica, sus tareas y las subtareas de éstas; registradas y automáticas). */
CREATE OR ALTER PROCEDURE api.Epicas_Avance
    @Proyecto  varchar(50) = NULL,
    @Categoria varchar(20) = NULL,      -- new | indeterminate | done
    @Texto     nvarchar(100) = NULL     -- en la clave o el resumen de la épica
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.Clave AS Epica, e.Resumen, e.ProyectoClave, e.Estado, e.CategoriaEstado, e.Responsable,
           ISNULL(c.Issues, 0) AS Issues, ISNULL(c.Terminados, 0) AS Terminados,
           CAST(CASE WHEN c.Issues > 0 THEN 100.0 * c.Terminados / c.Issues END AS decimal(5,1)) AS PorcentajeAvance,
           c.StoryPoints, c.StoryPointsTerminados,
           e.HorasEstimadasArbol AS HorasEstimadas, e.HorasRegistradasArbol AS HorasRegistradas,
           e.HorasAutomaticasArbol AS HorasAutomaticas, e.UltimoRegistroArbol AS UltimoRegistro,
           e.Creado, e.Vencimiento, e.Resuelto
    FROM rpt.vIssue e
    OUTER APPLY (
        SELECT COUNT(*) AS Issues,
               SUM(CASE WHEN t.CategoriaEstado = 'done' THEN 1 ELSE 0 END) AS Terminados,
               SUM(t.StoryPoints) AS StoryPoints,
               SUM(CASE WHEN t.CategoriaEstado = 'done' THEN t.StoryPoints END) AS StoryPointsTerminados
        FROM rpt.vIssue t
        WHERE t.FuenteId = e.FuenteId AND t.PadreId = e.IssueId AND t.NivelJerarquia = 0
    ) c
    WHERE e.NivelJerarquia >= 1
      AND (@Proyecto IS NULL OR e.ProyectoClave = @Proyecto)
      AND (@Categoria IS NULL OR e.CategoriaEstado = @Categoria)
      AND (@Texto IS NULL OR CHARINDEX(@Texto, CONCAT(e.Clave, N' ', e.Resumen)) > 0)
    ORDER BY CASE e.CategoriaEstado WHEN 'indeterminate' THEN 0 WHEN 'new' THEN 1 ELSE 2 END, e.UltimoRegistroArbol DESC, e.Clave;
END;
GO
