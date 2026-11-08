/* Horas registradas por persona y proyecto en un periodo (por fecha de inicio del worklog). */
CREATE OR ALTER PROCEDURE api.Horas_PorPersona
    @Desde        date,
    @Hasta        date,
    @Proyecto     varchar(50) = NULL,
    @TipoProyecto varchar(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT w.Autor, w.TipoCuentaAutor, w.ProyectoClave, w.TipoProyecto,
           COUNT(DISTINCT w.IssueSk) AS Issues, COUNT(*) AS Registros, SUM(w.Horas) AS Horas
    FROM rpt.vWorklog w
    WHERE w.Fecha BETWEEN @Desde AND @Hasta
      AND (@Proyecto IS NULL OR w.ProyectoClave = @Proyecto)
      AND (@TipoProyecto IS NULL OR w.TipoProyecto = @TipoProyecto)
    GROUP BY w.Autor, w.TipoCuentaAutor, w.ProyectoClave, w.TipoProyecto
    ORDER BY Horas DESC;
END;
GO
