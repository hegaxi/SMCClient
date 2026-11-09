/* Después de integrar issues, worklogs o historial: recalcula la atribución de los worklogs y el resumen por issue
   (ops.IssueResumen) solo para los issues tocados en esta pasada (documentos procesados desde @Desde).
   Lo llama sync.Procesar_Pendientes al terminar cada entidad. */
CREATE OR ALTER PROCEDURE sync.Derivados_Actualizar
    @FuenteId int,
    @Entidad  varchar(40),
    @Desde    datetimeoffset(3)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Entidad NOT IN ('issue', 'changelog', 'worklog', 'worklog_eliminado') RETURN;
    DECLARE @issues sync.IdTipo;

    IF @Entidad IN ('issue', 'changelog')
        INSERT @issues (IdExterno)
        SELECT DISTINCT LEFT(d.IdExterno, 100) FROM raw.Documento d
        WHERE d.FuenteId = @FuenteId AND d.Entidad = @Entidad AND d.Procesado = 1 AND d.ProcesadoEn >= @Desde;
    ELSE
        INSERT @issues (IdExterno)
        SELECT DISTINCT w.IssueId FROM raw.Documento d
        JOIN ops.Worklog w ON w.FuenteId = d.FuenteId
         AND w.WorklogId = CAST(COALESCE(JSON_VALUE(d.Json, '$.worklogId'), JSON_VALUE(d.Json, '$.id'), d.IdExterno) AS varchar(30))
        WHERE d.FuenteId = @FuenteId AND d.Entidad = @Entidad AND d.Procesado = 1 AND d.ProcesadoEn >= @Desde;

    IF NOT EXISTS (SELECT 1 FROM @issues) RETURN;

    -- Un worklog nuevo, editado o borrado puede cambiar si los automáticos de OTROS issues son copia suya
    -- (sync.Worklog_Atribuir): se recalculan también esos issues.
    INSERT @issues (IdExterno)
    SELECT DISTINCT a.IssueId
    FROM ops.Worklog t
    JOIN ops.Worklog a ON a.FuenteId = t.FuenteId AND a.Segundos = t.Segundos
     AND a.Creado BETWEEN DATEADD(hour, -2, t.Creado) AND DATEADD(hour, 2, t.Creado)
    WHERE t.FuenteId = @FuenteId AND t.IssueId IN (SELECT IdExterno FROM @issues)
      AND a.EsAutomatico = 1 AND a.IssueId NOT IN (SELECT IdExterno FROM @issues);
    EXEC sync.Worklog_Atribuir @FuenteId = @FuenteId, @Issues = @issues;
    EXEC sync.Resumen_Recalcular @FuenteId = @FuenteId, @Issues = @issues;
END;
GO
