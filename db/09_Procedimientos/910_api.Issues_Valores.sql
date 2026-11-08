/* Valores existentes de un campo de lista (con cuántos issues tiene cada uno), para el selector del buscador.
   EXECUTE AS OWNER: arma SQL con la expresión del campo, que sale de la lista blanca (rpt.fn_CamposBuscador);
   el texto de búsqueda viaja como parámetro. */
CREATE OR ALTER PROCEDURE api.Issues_Valores
    @Campo varchar(60),
    @Texto nvarchar(100) = NULL,
    @Top   int = 100
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @tipo varchar(10), @expr nvarchar(600), @multi nvarchar(600);
    SELECT @tipo = Tipo, @expr = Expresion, @multi = ExpresionMulti FROM rpt.fn_CamposBuscador() WHERE Clave = @Campo;
    IF @tipo IS NULL THROW 50404, 'El campo no existe.', 1;
    IF @tipo NOT IN ('lista', 'usuario', 'texto') THROW 50400, 'Solo los campos de texto o de lista tienen valores para elegir.', 1;
    IF @Top NOT BETWEEN 1 AND 500 SET @Top = 100;

    DECLARE @fuente nvarchar(max) = CASE WHEN @multi IS NOT NULL
        THEN N'CROSS APPLY (' + @multi + N') m(v) CROSS APPLY (SELECT CAST(m.v AS nvarchar(400)) AS Valor) x'
        ELSE N'CROSS APPLY (SELECT CAST(' + @expr + N' AS nvarchar(400)) AS Valor) x' END;
    DECLARE @sql nvarchar(max) = N'
        SELECT TOP (@top) x.Valor, COUNT(DISTINCT i.IssueSk) AS Issues
        FROM rpt.vIssue i ' + @fuente + N'
        WHERE x.Valor IS NOT NULL AND x.Valor <> N'''' AND (@texto IS NULL OR CHARINDEX(@texto, x.Valor) > 0)
        GROUP BY x.Valor
        ORDER BY COUNT(DISTINCT i.IssueSk) DESC, x.Valor;';
    EXEC sp_executesql @sql, N'@top int, @texto nvarchar(100)', @top = @Top, @texto = @Texto;
END;
GO
