/* Resumen de una búsqueda avanzada calculado en SQL Server sobre TODOS los issues que cumplen los criterios
   (no solo una página): lo usan los widgets de barras e indicador de los tableros.
   @Criterios   los mismos de api.Issues_Consultar.
   @AgruparPor  clave de cualquier campo (vacío = un solo total). Fechas: por mes (aaaa-mm). Campos de varios valores
                (etiquetas, sprints…): un issue cuenta en cada uno de sus valores; sin valor = "(vacío)".
   @Agregacion  conteo | suma | promedio | maximo | minimo.   @Valor  campo numérico (obligatorio salvo en conteo).
   @Top         barras a devolver contando "Otros": @Top - 1 grupos y el resto juntos en "Otros" (cada issue una vez).
   Seguridad: igual que api.Issues_Consultar (lista blanca, valores leídos del JSON, EXECUTE AS OWNER). */
CREATE OR ALTER PROCEDURE api.Issues_Resumir
    @Criterios  nvarchar(max) = N'[]',
    @AgruparPor varchar(60) = NULL,
    @Agregacion varchar(10) = 'conteo',
    @Valor      varchar(60) = NULL,
    @Top        int = 10
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET @Criterios = ISNULL(NULLIF(LTRIM(RTRIM(@Criterios)), N''), N'[]');
    SET @Agregacion = ISNULL(NULLIF(@Agregacion, ''), 'conteo');
    SET @AgruparPor = NULLIF(@AgruparPor, '');
    SET @Valor = NULLIF(@Valor, '');
    IF @Top IS NULL OR @Top NOT BETWEEN 2 AND 100 SET @Top = 10;   -- incluye la barra "Otros"
    IF @Agregacion NOT IN ('conteo', 'suma', 'promedio', 'maximo', 'minimo')
        THROW 50400, 'Cálculo inválido: conteo, suma, promedio, maximo o minimo.', 1;
    DECLARE @hoy date = CAST(SYSDATETIMEOFFSET() AS date);

    DECLARE @where nvarchar(max);
    EXEC rpt.Buscador_Condiciones @Criterios = @Criterios, @Hoy = @hoy, @Where = @where OUTPUT;

    -- Valor a calcular (campo numérico; los personalizados se guardan como valores múltiples: se suman por issue).
    DECLARE @exprValor nvarchar(max) = N'CAST(NULL AS decimal(19,4))', @etqValor nvarchar(200) = NULL;
    IF @Agregacion <> 'conteo'
    BEGIN
        IF @Valor IS NULL THROW 50400, 'Indique el campo numérico a calcular.', 1;
        SELECT @exprValor = CASE WHEN ExpresionMulti IS NULL THEN N'CAST(' + Expresion + N' AS decimal(19,4))'
                                 ELSE N'(SELECT SUM(CAST(m.v AS decimal(19,4))) FROM (' + ExpresionMulti + N') m(v))' END,
               @etqValor = Etiqueta
        FROM rpt.fn_CamposBuscador() WHERE Clave = @Valor AND Tipo = 'numero';
        IF @etqValor IS NULL THROW 50400, 'El campo a calcular debe ser numérico.', 1;
    END;

    -- Grupo.
    DECLARE @tipoG varchar(10), @exprG nvarchar(600), @multiG nvarchar(600), @etqG nvarchar(200);
    IF @AgruparPor IS NOT NULL
    BEGIN
        SELECT @tipoG = Tipo, @exprG = Expresion, @multiG = ExpresionMulti, @etqG = Etiqueta FROM rpt.fn_CamposBuscador() WHERE Clave = @AgruparPor;
        IF @tipoG IS NULL THROW 50400, 'Campo para agrupar desconocido.', 1;
    END;
    DECLARE @x nvarchar(max) = CASE WHEN @multiG IS NOT NULL THEN N'm.v' ELSE @exprG END;
    DECLARE @grupo nvarchar(max) = CASE
        WHEN @AgruparPor IS NULL THEN N'CAST(NULL AS nvarchar(400))'
        WHEN @tipoG = 'fecha' THEN N'CONVERT(nvarchar(7), CAST(' + @x + N' AS date), 126)'
        WHEN @tipoG = 'bit'   THEN N'CASE WHEN ' + @x + N' = 1 THEN N''Sí'' ELSE N''No'' END'
        ELSE N'NULLIF(CAST(' + @x + N' AS nvarchar(400)), N'''')' END;
    DECLARE @apply nvarchar(max) = CASE WHEN @multiG IS NOT NULL THEN N' OUTER APPLY (' + @multiG + N') m(v)' ELSE N'' END;

    DECLARE @agg nvarchar(200) = CASE @Agregacion WHEN 'conteo' THEN N'COUNT(*)' WHEN 'suma' THEN N'SUM(v)' WHEN 'promedio' THEN N'AVG(v)'
                                                  WHEN 'maximo' THEN N'MAX(v)' ELSE N'MIN(v)' END;

    -- base: un renglón por (issue, grupo). Cada grupo y "Otros" se calculan sobre issues distintos.
    DECLARE @sql nvarchar(max) = N'
        WITH base AS (
            SELECT DISTINCT i.IssueSk, ' + @exprValor + N' AS v, ' + @grupo + N' AS g
            FROM rpt.vIssue i' + @apply + N'
            WHERE 1 = 1' + @where + N'),
        grupos AS (SELECT g, ' + @agg + N' AS Valor, COUNT(*) AS Issues FROM base GROUP BY g),
        rk AS (SELECT g, Valor, Issues, ROW_NUMBER() OVER (ORDER BY Valor DESC, Issues DESC, g) AS n, COUNT(*) OVER () AS total FROM grupos),
        resto AS (SELECT DISTINCT b.IssueSk, b.v FROM base b JOIN rk ON EXISTS (SELECT b.g INTERSECT SELECT rk.g) WHERE rk.total > @top AND rk.n >= @top)
        SELECT ISNULL(g, CASE WHEN @agrupado = 1 THEN N''(vacío)'' END) AS Grupo, CAST(Valor AS decimal(19,4)) AS Valor, Issues,
               1 AS Grupos, CAST(0 AS bit) AS EsOtros, @etqG AS EtiquetaGrupo, @etqV AS EtiquetaValor, n AS Posicion
        FROM rk WHERE rk.total <= @top OR rk.n < @top
        UNION ALL
        SELECT N''Otros'', CAST((SELECT ' + @agg + N' FROM resto) AS decimal(19,4)), (SELECT COUNT(*) FROM resto),
               (SELECT COUNT(*) FROM rk WHERE rk.n >= @top), CAST(1 AS bit), @etqG, @etqV, @top
        WHERE (SELECT MAX(total) FROM rk) > @top
        UNION ALL
        SELECT CAST(NULL AS nvarchar(400)), CAST(CASE WHEN @calc = ''conteo'' THEN 0 END AS decimal(19,4)), 0, 0, CAST(0 AS bit), @etqG, @etqV, 1
        WHERE @agrupado = 0 AND NOT EXISTS (SELECT 1 FROM rk)
        ORDER BY Posicion
        OPTION (RECOMPILE);';
    DECLARE @agrupado bit = CASE WHEN @AgruparPor IS NULL THEN 0 ELSE 1 END;
    EXEC sp_executesql @sql, N'@c nvarchar(max), @hoy date, @top int, @agrupado bit, @calc varchar(10), @etqG nvarchar(200), @etqV nvarchar(200)',
         @c = @Criterios, @hoy = @hoy, @top = @Top, @agrupado = @agrupado, @calc = @Agregacion, @etqG = @etqG, @etqV = @etqValor;
END;
GO
