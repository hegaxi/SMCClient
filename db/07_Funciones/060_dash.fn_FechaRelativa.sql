/* Fechas relativas de los filtros guardados, para que un tablero siempre muestre datos actuales:
   {hoy}  {hoy-30}  {hoy+7}  {inicio_semana} (lunes)  {inicio_mes}  {inicio_mes_anterior}  {fin_mes_anterior}  {inicio_anio}
   Devuelve NULL si el texto no es una fecha relativa. */
CREATE OR ALTER FUNCTION dash.fn_FechaRelativa (@valor nvarchar(100), @hoy date)
RETURNS date
AS
BEGIN
    IF @valor NOT LIKE N'{%}' RETURN NULL;
    DECLARE @t nvarchar(100) = LOWER(SUBSTRING(@valor, 2, LEN(@valor) - 2));
    IF @t = N'hoy' RETURN @hoy;
    IF @t LIKE N'hoy[+-]%' AND TRY_CAST(SUBSTRING(@t, 5, 10) AS int) IS NOT NULL
        RETURN DATEADD(DAY, CASE WHEN SUBSTRING(@t, 4, 1) = N'-' THEN -1 ELSE 1 END * CAST(SUBSTRING(@t, 5, 10) AS int), @hoy);
    IF @t = N'inicio_semana' RETURN DATEADD(DAY, -((DATEPART(WEEKDAY, @hoy) + @@DATEFIRST - 2) % 7), @hoy);
    IF @t = N'inicio_mes' RETURN DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1);
    IF @t = N'inicio_mes_anterior' RETURN DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1));
    IF @t = N'fin_mes_anterior' RETURN DATEADD(DAY, -1, DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1));
    IF @t = N'inicio_anio' RETURN DATEFROMPARTS(YEAR(@hoy), 1, 1);
    RETURN NULL;
END;
GO
