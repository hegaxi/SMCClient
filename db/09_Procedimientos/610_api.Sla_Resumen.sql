/* Cumplimiento de SLA por proyecto y SLA, para tickets creados en el periodo. */
CREATE OR ALTER PROCEDURE api.Sla_Resumen
    @Desde    date,
    @Hasta    date,
    @Proyecto varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.ProyectoClave, s.Sla,
           COUNT(*) AS Ciclos,
           SUM(CASE WHEN s.EnCurso = 0 AND s.Incumplido = 0 THEN 1 ELSE 0 END) AS Cumplidos,
           SUM(CASE WHEN s.Incumplido = 1 THEN 1 ELSE 0 END) AS Incumplidos,
           SUM(CASE WHEN s.EnCurso = 1 AND s.Incumplido = 0 THEN 1 ELSE 0 END) AS EnCurso,
           CAST(100.0 * SUM(CASE WHEN s.Incumplido = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS decimal(5,1)) AS PorcentajeCumplimiento,
           CAST(AVG(CASE WHEN s.EnCurso = 0 THEN s.TranscurridoMs / 3600000.0 END) AS decimal(10,2)) AS HorasPromedio
    FROM rpt.vSla s
    JOIN ops.Issue i ON i.IssueSk = s.IssueSk
    WHERE i.Creado >= CAST(@Desde AS datetimeoffset(3)) AND i.Creado < DATEADD(DAY, 1, CAST(@Hasta AS datetimeoffset(3)))
      AND (@Proyecto IS NULL OR s.ProyectoClave = @Proyecto)
    GROUP BY s.ProyectoClave, s.Sla
    ORDER BY s.ProyectoClave, s.Sla;
END;
GO
