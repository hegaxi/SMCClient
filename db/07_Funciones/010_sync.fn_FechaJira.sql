/* Convierte las fechas de Jira a datetimeoffset.
   Jira envía '2026-07-08T09:30:36.291-0600' (sin ':' en la zona), que SQL Server no acepta directo.
   También acepta '...Z', '...-06:00' y fechas simples '2026-09-07'. Devuelve NULL si no la reconoce. */
CREATE OR ALTER FUNCTION sync.fn_FechaJira (@valor nvarchar(60))
RETURNS datetimeoffset(3)
WITH SCHEMABINDING
AS
BEGIN
    RETURN TRY_CONVERT(datetimeoffset(3),
        CASE
            WHEN @valor LIKE N'%T%[+-][0-9][0-9][0-9][0-9]' THEN STUFF(@valor, LEN(@valor) - 1, 0, N':')
            ELSE @valor
        END, 127);
END;
GO
