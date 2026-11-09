/* Devuelve el JSON de parámetros con las fechas relativas convertidas a fechas (yyyy-mm-dd). */
CREATE OR ALTER FUNCTION dash.fn_ResolverParametros (@json nvarchar(max), @hoy date)
RETURNS nvarchar(max)
AS
BEGIN
    IF @json IS NULL OR ISJSON(@json) = 0 RETURN N'{}';
    RETURN ISNULL((
        SELECT N'{' + STRING_AGG(CAST(CONCAT(N'"', STRING_ESCAPE(j.[key], 'json'), N'":',
               CASE WHEN j.type = 1 AND f.Fecha IS NOT NULL THEN CONCAT(N'"', CONVERT(char(10), f.Fecha, 23), N'"')
                    WHEN j.type = 1 THEN CONCAT(N'"', STRING_ESCAPE(j.value, 'json'), N'"')
                    ELSE j.value END) AS nvarchar(max)), N',') + N'}'
        FROM OPENJSON(@json) j
        CROSS APPLY (SELECT CASE WHEN j.type = 1 THEN dash.fn_FechaRelativa(j.value, @hoy) END AS Fecha) f
    ), N'{}');
END;
GO
