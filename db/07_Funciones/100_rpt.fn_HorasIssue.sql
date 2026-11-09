/* Horas registradas y automáticas, estimación y último registro de un issue con TODOS sus descendientes (una tarea
   con sus subtareas; una épica con sus tareas y las subtareas de éstas). Lee ops.IssueResumen, que se calcula al
   integrar (sync.Resumen_Recalcular). NULL = no tiene worklogs de ese origen. @Clave se conserva por compatibilidad. */
CREATE OR ALTER FUNCTION rpt.fn_HorasIssue (@FuenteId int, @IssueId varchar(30), @Clave varchar(50))
RETURNS TABLE
AS
RETURN
    SELECT CAST(r.SegRegArbol / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(r.SegAutArbol / 3600.0 AS decimal(12,2)) AS HorasAutomaticas,      -- sin copias
           CAST(r.SegCopiaArbol / 3600.0 AS decimal(12,2)) AS HorasCopiadas,       -- copias automáticas (no se suman)
           r.UltimoRegistroArbol AS UltimoRegistro,
           CAST(r.EstimacionArbolSeg / 3600.0 AS decimal(12,2)) AS HorasEstimadas
    FROM ops.Issue i
    JOIN ops.IssueResumen r ON r.IssueSk = i.IssueSk
    WHERE i.FuenteId = @FuenteId AND i.IssueId = @IssueId;
GO
