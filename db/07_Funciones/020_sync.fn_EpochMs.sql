/* Milisegundos desde 1970-01-01 UTC (formato de los SLA de JSM) a datetimeoffset. */
CREATE OR ALTER FUNCTION sync.fn_EpochMs (@ms bigint)
RETURNS datetimeoffset(3)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN @ms IS NULL THEN NULL ELSE
        DATEADD(MILLISECOND, CAST(@ms % 86400000 AS int),
            DATEADD(DAY, CAST(@ms / 86400000 AS int), CAST('1970-01-01T00:00:00+00:00' AS datetimeoffset(3)))) END;
END;
GO
