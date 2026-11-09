/* Convierte las fechas de Jira a datetimeoffset.
   Jira envía '2026-07-08T09:30:36.291-0600' (sin ':' en la zona), que SQL Server no acepta directo.
   También acepta '...Z', '...-06:00', fechas simples '2026-09-07' y milisegundos desde 1970 UTC
   ('1707361702993', como los devuelve POST /changelog/bulkfetch). Devuelve NULL si no la reconoce. */
CREATE OR ALTER FUNCTION sync.fn_FechaJira (@valor nvarchar(60))
RETURNS datetimeoffset(3)
WITH SCHEMABINDING
AS
BEGIN
    IF LEN(@valor) BETWEEN 10 AND 15 AND @valor NOT LIKE N'%[^0-9]%'
    BEGIN
        DECLARE @ms bigint = CAST(@valor AS bigint);
        RETURN DATEADD(MILLISECOND, CAST(@ms % 86400000 AS int),
            DATEADD(DAY, CAST(@ms / 86400000 AS int), CAST('1970-01-01T00:00:00+00:00' AS datetimeoffset(3))));
    END;
    RETURN TRY_CONVERT(datetimeoffset(3),
        CASE
            WHEN @valor LIKE N'%T%[+-][0-9][0-9][0-9][0-9]' THEN STUFF(@valor, LEN(@valor) - 1, 0, N':')
            ELSE @valor
        END, 127);
END;
GO
