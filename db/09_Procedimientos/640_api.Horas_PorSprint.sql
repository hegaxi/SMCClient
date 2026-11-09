/* Tiempo reportado en Scrum: horas por sprint y persona.
   Cuenta los worklogs registrados dentro de las fechas del sprint (ver api.Sprint_Avance) en los issues del sprint y
   en sus subtareas (donde las personas suelen registrar el tiempo). Las horas automáticas (Automation for Jira) se
   atribuyen al responsable del issue ese día, igual que en api.Horas_PorPersona (rpt.vWorklog). */
CREATE OR ALTER PROCEDURE api.Horas_PorSprint
    @Proyecto varchar(50) = NULL,
    @Estado   varchar(20) = NULL,       -- future | active | closed
    @Sprint   nvarchar(255) = NULL      -- parte del nombre
AS
BEGIN
    SET NOCOUNT ON;
    WITH s AS (
        SELECT s.FuenteId, s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin,
               COALESCE(s.Completado, CASE WHEN s.Estado = 'active' AND SYSDATETIMEOFFSET() > s.Fin THEN SYSDATETIMEOFFSET() END, s.Fin) AS FinEfectivo
        FROM ops.Sprint s
        WHERE (@Estado IS NULL OR s.Estado = @Estado) AND (@Sprint IS NULL OR CHARINDEX(@Sprint, s.Nombre) > 0)
    ),
    iss AS (
        SELECT x.FuenteId, x.SprintId, i.IssueSk, i.Clave
        FROM ops.IssueSprint x JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
        WHERE @Proyecto IS NULL OR i.ProyectoClave = @Proyecto
    )
    SELECT s.Nombre AS Sprint, s.Estado, s.Inicio, s.Fin, w.AtribuidoA AS Persona,
           COUNT(DISTINCT w.IssueSk) AS Issues,
           CAST(SUM(CASE WHEN w.Origen = 'manual' THEN w.Horas ELSE 0 END) AS decimal(12,2)) AS HorasRegistradas,
           CAST(SUM(CASE WHEN w.Origen = 'automatico' THEN w.Horas ELSE 0 END) AS decimal(12,2)) AS HorasAutomaticas,
           CAST(SUM(w.Horas) AS decimal(12,2)) AS HorasTotales
    FROM s
    JOIN rpt.vWorklog w ON w.FuenteId = s.FuenteId AND w.Inicio >= s.Inicio AND w.Inicio < s.FinEfectivo
    JOIN ops.Issue wi ON wi.IssueSk = w.IssueSk
    WHERE EXISTS (SELECT 1 FROM iss WHERE iss.FuenteId = s.FuenteId AND iss.SprintId = s.SprintId AND iss.IssueSk = w.IssueSk)
       OR (wi.EsSubtarea = 1 AND EXISTS (SELECT 1 FROM iss WHERE iss.FuenteId = s.FuenteId AND iss.SprintId = s.SprintId AND iss.Clave = wi.PadreClave))
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin, w.AtribuidoA
    ORDER BY s.Inicio DESC, HorasRegistradas DESC, HorasTotales DESC;
END;
GO
