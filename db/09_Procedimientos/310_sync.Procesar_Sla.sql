/* SLA de JSM (GET /rest/servicedeskapi/request/{id}/sla, páginas unidas en un documento).
   Se usa este endpoint y no el campo SLA del issue porque, con slaDisplayFormat NEW_SLA_FORMAT,
   la búsqueda no trae el ciclo en curso. Contrato: IdExterno = id del issue; {"values":[...]}.
   Es una foto: se reemplazan todos los SLA del ticket. Un SLA nuevo en JSM aparece solo. */
CREATE OR ALTER PROCEDURE sync.Procesar_Sla
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DocumentoId, i.IssueSk, d.Json
    INTO #k
    FROM #lote l
    JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
    LEFT JOIN ops.Issue i ON i.FuenteId = @FuenteId AND i.IssueId = d.IdExterno;

    DELETE l FROM #lote l JOIN #k k ON k.DocumentoId = l.DocumentoId WHERE k.IssueSk IS NULL;
    DELETE FROM #k WHERE IssueSk IS NULL;

    SELECT k.IssueSk, s.SlaId, s.Nombre, s.EnCurso, s.Completados
    INTO #s
    FROM #k k
    CROSS APPLY OPENJSON(COALESCE(JSON_QUERY(k.Json, '$.values'), k.Json))
        WITH (SlaId varchar(30) '$.id', Nombre nvarchar(255) '$.name',
              EnCurso nvarchar(max) '$.ongoingCycle' AS JSON, Completados nvarchar(max) '$.completedCycles' AS JSON) s
    WHERE s.SlaId IS NOT NULL;

    DELETE x FROM ops.IssueSla x JOIN #k k ON k.IssueSk = x.IssueSk;

    INSERT ops.IssueSla (IssueSk, SlaId, Ciclo, Nombre, EnCurso, Inicio, Fin, Vencimiento, ObjetivoMs, TranscurridoMs, RestanteMs, Incumplido, Pausado, EnHorarioLaboral)
    SELECT s.IssueSk, s.SlaId, c.Ciclo, ISNULL(s.Nombre, s.SlaId), c.EnCurso,
           sync.fn_EpochMs(y.Inicio), sync.fn_EpochMs(y.Fin), sync.fn_EpochMs(y.Vence),
           y.Objetivo, y.Transcurrido, y.Restante, y.Incumplido, y.Pausado, y.EnHorario
    FROM #s s
    CROSS APPLY (
        SELECT CAST(0 AS smallint) AS Ciclo, CAST(1 AS bit) AS EnCurso, s.EnCurso AS J WHERE s.EnCurso IS NOT NULL
        UNION ALL
        SELECT CAST(cc.[key] AS smallint) + 1, CAST(0 AS bit), cc.value FROM OPENJSON(s.Completados) cc
    ) c
    CROSS APPLY OPENJSON(c.J) WITH (
        Inicio bigint '$.startTime.epochMillis', Fin bigint '$.stopTime.epochMillis', Vence bigint '$.breachTime.epochMillis',
        Objetivo bigint '$.goalDuration.millis', Transcurrido bigint '$.elapsedTime.millis', Restante bigint '$.remainingTime.millis',
        Incumplido bit '$.breached', Pausado bit '$.paused', EnHorario bit '$.withinCalendarHours') y;
END;
GO
