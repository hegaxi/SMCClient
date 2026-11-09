/* Horas por persona y proyecto en un periodo (por fecha de inicio del worklog).
   Separa las horas que registraron las personas (esfuerzo) de las automáticas (Automation for Jira:
   días hábiles con el issue abierto), atribuidas al responsable del issue ese día. Ver rpt.vWorklog.
   Ojo: las automáticas suman 8 h por cada issue abierto, así que una persona con varios issues abiertos
   puede acumular más de 8 h automáticas en un día. */
CREATE OR ALTER PROCEDURE api.Horas_PorPersona
    @Desde        date,
    @Hasta        date,
    @Proyecto     varchar(50) = NULL,
    @TipoProyecto varchar(30) = NULL,
    @Origen       varchar(12) = NULL,     -- manual | automatico | NULL = ambos
    @Epica        varchar(50) = NULL      -- clave de una épica: solo el tiempo de la épica, sus tareas y subtareas
AS
BEGIN
    SET NOCOUNT ON;
    IF @Origen IS NOT NULL AND @Origen NOT IN ('manual', 'automatico')
        THROW 50400, 'Origen debe ser manual o automatico.', 1;

    -- Épica pedida por su clave (en cada fuente): se filtra por la épica precalculada de cada issue.
    DECLARE @epicas TABLE (FuenteId int, IssueId varchar(30), PRIMARY KEY (FuenteId, IssueId));
    IF @Epica IS NOT NULL INSERT @epicas SELECT FuenteId, IssueId FROM ops.Issue WHERE Clave = @Epica AND Eliminado = 0;

    SELECT w.AtribuidoA AS Persona, w.ProyectoClave, w.TipoProyecto,
           COUNT(DISTINCT w.IssueSk) AS Issues,
           CAST(SUM(CASE WHEN w.Origen = 'manual' THEN w.Horas ELSE 0 END) AS decimal(12,2)) AS HorasRegistradas,
           CAST(SUM(CASE WHEN w.Origen = 'automatico' THEN w.Horas ELSE 0 END) AS decimal(12,2)) AS HorasAutomaticas,
           CAST(SUM(w.Horas) AS decimal(12,2)) AS HorasTotales
    FROM rpt.vWorklog w
    WHERE w.Fecha BETWEEN @Desde AND @Hasta
      -- Rango amplio sobre la columna indexada (la fecha local del worklog puede diferir un día de la UTC).
      AND w.Inicio >= DATEADD(DAY, -1, CAST(@Desde AS datetimeoffset(3))) AND w.Inicio < DATEADD(DAY, 2, CAST(@Hasta AS datetimeoffset(3)))
      AND (@Proyecto IS NULL OR w.ProyectoClave = @Proyecto)
      AND (@TipoProyecto IS NULL OR w.TipoProyecto = @TipoProyecto)
      AND (@Origen IS NULL OR w.Origen = @Origen)
      AND (@Epica IS NULL OR EXISTS (SELECT 1 FROM ops.IssueResumen r JOIN @epicas e ON e.FuenteId = r.FuenteId AND e.IssueId = r.EpicaIssueId
                                     WHERE r.IssueSk = w.IssueSk))
    GROUP BY w.AtribuidoA, w.ProyectoClave, w.TipoProyecto
    ORDER BY HorasRegistradas DESC, HorasTotales DESC
    OPTION (RECOMPILE);
END;
GO
