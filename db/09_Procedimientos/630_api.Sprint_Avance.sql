/* Avance por sprint: issues, terminados, story points y horas. */
CREATE OR ALTER PROCEDURE api.Sprint_Avance
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL    -- future | active | closed
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SprintId, s.Nombre AS Sprint, s.Estado, s.Inicio, s.Fin, s.Completado,
           COUNT(*) AS Issues,
           SUM(CASE WHEN i.CategoriaEstado = 'done' THEN 1 ELSE 0 END) AS Terminados,
           SUM(i.StoryPoints) AS StoryPoints,
           SUM(CASE WHEN i.CategoriaEstado = 'done' THEN i.StoryPoints END) AS StoryPointsTerminados,
           CAST(SUM(i.TiempoInvertidoSeg) / 3600.0 AS decimal(12,2)) AS HorasInvertidas
    FROM ops.Sprint s
    JOIN ops.IssueSprint x ON x.FuenteId = s.FuenteId AND x.SprintId = s.SprintId
    JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
    WHERE (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto) AND (@Estado IS NULL OR s.Estado = @Estado)
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, s.Completado
    ORDER BY s.Inicio DESC;
END;
GO
