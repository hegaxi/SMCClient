/* Minutos a texto corto para personas: 130 -> '2 h 10 min', 3000 -> '2 d 2 h', -4560 -> 'hace 3 d 4 h'. */
CREATE OR ALTER FUNCTION rpt.fn_DuracionTexto (@Minutos int)
RETURNS nvarchar(40)
WITH SCHEMABINDING
AS
BEGIN
    IF @Minutos IS NULL RETURN NULL;
    DECLARE @m int = ABS(@Minutos);
    DECLARE @t nvarchar(40) =
        CASE WHEN @m >= 1440 THEN CONCAT(@m / 1440, N' d', CASE WHEN (@m % 1440) / 60 > 0 THEN CONCAT(N' ', (@m % 1440) / 60, N' h') END)
             WHEN @m >= 60   THEN CONCAT(@m / 60, N' h', CASE WHEN @m % 60 > 0 THEN CONCAT(N' ', @m % 60, N' min') END)
             ELSE CONCAT(@m, N' min') END;
    RETURN CASE WHEN @Minutos < 0 THEN N'hace ' + @t ELSE @t END;
END;
GO
