/* Épica a la que pertenece un issue (él mismo si es épica, o su antecesor más cercano de nivel épica), unida por id de
   Jira. Lee ops.IssueResumen, que se calcula al integrar. Devuelve la clave ACTUAL de la épica y un texto
   "CLAVE · Resumen". @PadreId y @Nivel se conservan por compatibilidad. */
CREATE OR ALTER FUNCTION rpt.fn_EpicaIssue (@FuenteId int, @IssueId varchar(30), @PadreId varchar(30), @Nivel smallint)
RETURNS TABLE
AS
RETURN
    SELECT e.Clave AS EpicaClave, CAST(CONCAT(e.Clave, N' · ', LEFT(e.Resumen, 150)) AS nvarchar(220)) AS Epica
    FROM ops.Issue i
    JOIN ops.IssueResumen r ON r.IssueSk = i.IssueSk
    JOIN ops.Issue e ON e.FuenteId = i.FuenteId AND e.IssueId = r.EpicaIssueId AND e.Eliminado = 0
    WHERE i.FuenteId = @FuenteId AND i.IssueId = @IssueId;
GO
