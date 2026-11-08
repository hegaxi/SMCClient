/* Búsqueda avanzada de issues (como el navegador de Jira): criterios sobre cualquier campo, columnas a elegir y orden.
   @Criterios: [{"campo":"estado","operador":"no_en","valores":["Done"]},
               {"campo":"creado","operador":"desde","valor":"{hoy-30}"},
               {"campo":"cf:customfield_10070","operador":"en","valores":["Incidente"]}, ...]
   @Columnas: claves separadas por coma, en el orden deseado (vacío = las predeterminadas). La clave siempre va primero.

   Seguridad: el SQL se arma SOLO con expresiones de la lista blanca (rpt.fn_CamposBuscador) y operadores conocidos;
   cada valor se lee del JSON @c dentro de la consulta (JSON_VALUE / OPENJSON con índices numéricos), nunca se concatena.
   EXECUTE AS OWNER porque el SQL dinámico no hereda el encadenamiento de propietarios (el rol smc_api no lee tablas). */
CREATE OR ALTER PROCEDURE api.Issues_Consultar
    @Criterios    nvarchar(max) = N'[]',
    @Columnas     nvarchar(2000) = NULL,
    @OrdenarPor   varchar(60) = NULL,
    @Descendente  bit = 1,
    @Pagina       int = 1,
    @TamanoPagina int = 50
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET @Criterios = ISNULL(NULLIF(LTRIM(RTRIM(@Criterios)), N''), N'[]');
    IF ISJSON(@Criterios) = 0 OR LEFT(LTRIM(@Criterios), 1) <> N'[' THROW 50400, 'Los criterios deben ser un arreglo JSON.', 1;
    IF @Pagina IS NULL OR @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 500 SET @TamanoPagina = 50;
    DECLARE @hoy date = CAST(SYSDATETIMEOFFSET() AS date), @msg nvarchar(1000);

    SELECT * INTO #campos FROM rpt.fn_CamposBuscador();

    SELECT CAST(j.[key] AS int) AS k, JSON_VALUE(j.value, '$.campo') AS Campo, JSON_VALUE(j.value, '$.operador') AS Operador,
           JSON_VALUE(j.value, '$.valor') AS Valor, JSON_VALUE(j.value, '$.hasta') AS Hasta,
           (SELECT COUNT(*) FROM OPENJSON(j.value, '$.valores')) AS NumValores
    INTO #crit
    FROM OPENJSON(@Criterios) j;

    IF (SELECT COUNT(*) FROM #crit) > 40 THROW 50400, 'Demasiados criterios (máximo 40).', 1;

    -- Validaciones (mensajes con el nombre del campo, para el usuario).
    SET @msg = (SELECT STRING_AGG(ISNULL(c.Campo, N'(sin campo)'), N', ') FROM #crit c WHERE NOT EXISTS (SELECT 1 FROM #campos f WHERE f.Clave = c.Campo));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Campos desconocidos: ' + @msg + N'.'; THROW 50400, @msg, 1; END;
    SET @msg = (SELECT STRING_AGG(CONCAT(f.Etiqueta, N' (', ISNULL(c.Operador, N'sin operador'), N')'), N', ')
                FROM #crit c JOIN #campos f ON f.Clave = c.Campo
                WHERE c.Operador IS NULL OR c.Operador NOT IN (SELECT value FROM STRING_SPLIT(f.Operadores, ',')));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Operador no válido para: ' + @msg + N'.'; THROW 50400, @msg, 1; END;
    SET @msg = (SELECT STRING_AGG(f.Etiqueta, N', ') FROM #crit c JOIN #campos f ON f.Clave = c.Campo
                WHERE (c.Operador IN ('en', 'no_en') AND c.NumValores = 0)
                   OR (c.Operador NOT IN ('en', 'no_en', 'vacio', 'no_vacio') AND NULLIF(c.Valor, N'') IS NULL)
                   OR (c.Operador = 'entre' AND NULLIF(c.Hasta, N'') IS NULL)
                   OR (f.Tipo = 'numero' AND c.Operador NOT IN ('vacio', 'no_vacio') AND (TRY_CAST(c.Valor AS decimal(19,4)) IS NULL OR (c.Operador = 'entre' AND TRY_CAST(c.Hasta AS decimal(19,4)) IS NULL)))
                   OR (f.Tipo = 'fecha' AND c.Operador NOT IN ('vacio', 'no_vacio')
                       AND (COALESCE(dash.fn_FechaRelativa(c.Valor, @hoy), TRY_CONVERT(date, c.Valor)) IS NULL
                            OR (c.Operador = 'entre' AND COALESCE(dash.fn_FechaRelativa(c.Hasta, @hoy), TRY_CONVERT(date, c.Hasta)) IS NULL)))
                   OR (f.Tipo = 'bit' AND TRY_CAST(c.Valor AS bit) IS NULL));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Falta un valor válido en: ' + @msg + N'.'; THROW 50400, @msg, 1; END;

    /* Condiciones ---------------------------------------------------------------------------------------- */
    DECLARE @where nvarchar(max) = N'';
    DECLARE @k int, @op varchar(20), @tipo varchar(10), @expr nvarchar(600), @multi nvarchar(600);
    DECLARE @x nvarchar(max), @v nvarchar(max), @h nvarchar(max), @lista nvarchar(max), @p nvarchar(max), @cond nvarchar(max);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.k, c.Operador, f.Tipo, f.Expresion, f.ExpresionMulti FROM #crit c JOIN #campos f ON f.Clave = c.Campo ORDER BY c.k;
    OPEN c; FETCH c INTO @k, @op, @tipo, @expr, @multi;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @rv nvarchar(100) = CONCAT(N'JSON_VALUE(@c, ''$[', @k, N'].valor'')');
        DECLARE @rh nvarchar(100) = CONCAT(N'JSON_VALUE(@c, ''$[', @k, N'].hasta'')');
        SET @lista = CONCAT(N'(SELECT value COLLATE DATABASE_DEFAULT FROM OPENJSON(@c, ''$[', @k, N'].valores''))');
        SET @v = CASE @tipo WHEN 'numero' THEN N'TRY_CAST(' + @rv + N' AS decimal(19,4))'
                            WHEN 'fecha'  THEN N'COALESCE(dash.fn_FechaRelativa(' + @rv + N', @hoy), TRY_CONVERT(date, ' + @rv + N'))'
                            WHEN 'bit'    THEN N'TRY_CAST(' + @rv + N' AS bit)'
                            ELSE @rv END;
        SET @h = CASE @tipo WHEN 'numero' THEN N'TRY_CAST(' + @rh + N' AS decimal(19,4))'
                            WHEN 'fecha'  THEN N'COALESCE(dash.fn_FechaRelativa(' + @rh + N', @hoy), TRY_CONVERT(date, ' + @rh + N'))'
                            ELSE @rh END;
        SET @x = CASE WHEN @multi IS NOT NULL THEN N'm.v' ELSE @expr END;
        IF @tipo = 'fecha' SET @x = N'CAST(' + @x + N' AS date)';

        -- Predicado positivo; los operadores negativos lo niegan.
        SET @p = CASE @op
            WHEN 'en' THEN @x + N' IN ' + @lista              WHEN 'no_en' THEN @x + N' IN ' + @lista
            WHEN 'contiene' THEN N'CHARINDEX(' + @v + N', ' + @x + N') > 0'
            WHEN 'no_contiene' THEN N'CHARINDEX(' + @v + N', ' + @x + N') > 0'
            WHEN 'igual' THEN @x + N' = ' + @v                 WHEN 'distinto' THEN @x + N' = ' + @v
            WHEN 'mayor' THEN @x + N' > ' + @v                 WHEN 'mayor_igual' THEN @x + N' >= ' + @v
            WHEN 'menor' THEN @x + N' < ' + @v                 WHEN 'menor_igual' THEN @x + N' <= ' + @v
            WHEN 'desde' THEN @x + N' >= ' + @v                WHEN 'hasta' THEN @x + N' <= ' + @v
            WHEN 'entre' THEN @x + N' BETWEEN ' + @v + N' AND ' + @h
            WHEN 'es' THEN N'ISNULL(' + @x + N', 0) = ' + @v
            WHEN 'vacio' THEN @x + N' IS NOT NULL AND CAST(' + @x + N' AS nvarchar(max)) <> N'''''
            WHEN 'no_vacio' THEN @x + N' IS NOT NULL AND CAST(' + @x + N' AS nvarchar(max)) <> N'''''
        END;
        DECLARE @negativo bit = CASE WHEN @op IN ('no_en', 'no_contiene', 'distinto', 'vacio') THEN 1 ELSE 0 END;

        IF @multi IS NOT NULL
            SET @cond = CASE WHEN @negativo = 1 THEN N'NOT ' ELSE N'' END + N'EXISTS (SELECT 1 FROM (' + @multi + N') m(v) WHERE ' + @p + N')';
        ELSE IF @op IN ('vacio', 'no_vacio')
            SET @cond = CASE WHEN @negativo = 1 THEN N'NOT ' ELSE N'' END + N'(' + @p + N')';
        ELSE
            SET @cond = CASE WHEN @negativo = 1 THEN N'NOT ' ELSE N'' END + N'(' + @p + N')';

        SET @where += N' AND ' + @cond;
        FETCH c INTO @k, @op, @tipo, @expr, @multi;
    END;
    CLOSE c; DEALLOCATE c;

    /* Columnas (en el orden pedido; la clave primero) ------------------------------------------------------ */
    DECLARE @jcols nvarchar(max) = N'["clave"' + CASE WHEN NULLIF(LTRIM(RTRIM(@Columnas)), N'') IS NULL
                                                     THEN ISNULL((SELECT N',"' + STRING_AGG(CAST(Clave AS nvarchar(max)), N'","') WITHIN GROUP (ORDER BY Orden) + N'"' FROM #campos WHERE ColumnaPredeterminada = 1 AND Clave <> 'clave'), N'')
                                                     ELSE N',"' + REPLACE(STRING_ESCAPE(REPLACE(@Columnas, N' ', N''), 'json'), N',', N'","') + N'"' END + N']';
    SELECT CAST(j.[key] AS int) AS Posicion, CAST(j.value AS varchar(60)) AS Clave
    INTO #cols FROM OPENJSON(@jcols) j WHERE j.value <> N'';
    SET @msg = (SELECT STRING_AGG(CAST(c.Clave AS nvarchar(60)), N', ') FROM #cols c WHERE NOT EXISTS (SELECT 1 FROM #campos f WHERE f.Clave = c.Clave COLLATE DATABASE_DEFAULT AND f.EsColumna = 1));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Columnas desconocidas: ' + @msg + N'.'; THROW 50400, @msg, 1; END;
    IF (SELECT COUNT(DISTINCT Clave) FROM #cols) > 40 THROW 50400, 'Demasiadas columnas (máximo 40).', 1;

    DECLARE @select nvarchar(max) = (
        SELECT STRING_AGG(CAST(u.Expr + N' AS ' + QUOTENAME(u.Nombre) AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY u.Posicion)
        FROM (
            SELECT u.Posicion,
                   CASE WHEN f.ExpresionMulti IS NOT NULL
                        THEN N'(SELECT STRING_AGG(CAST(m.v AS nvarchar(max)), N'', '') FROM (' + f.ExpresionMulti + N') m(v))'
                        ELSE f.Expresion END AS Expr,
                   -- Dos campos personalizados con el mismo nombre: se distinguen con su id.
                   CASE WHEN COUNT(*) OVER (PARTITION BY f.Alias) > 1 AND f.Origen <> N'Jira'
                        THEN LEFT(f.Alias, 90) + N' (' + f.Clave + N')' ELSE f.Alias END AS Nombre
            FROM (SELECT Clave, MIN(Posicion) AS Posicion FROM #cols GROUP BY Clave) u
            JOIN #campos f ON f.Clave = u.Clave COLLATE DATABASE_DEFAULT
        ) u);

    /* Orden --------------------------------------------------------------------------------------------- */
    DECLARE @orden nvarchar(700) = (SELECT Expresion FROM #campos WHERE Clave = ISNULL(NULLIF(@OrdenarPor, ''), 'actualizado'));
    IF @orden IS NULL THROW 50400, 'Solo se puede ordenar por campos de un solo valor.', 1;
    SET @orden += CASE WHEN ISNULL(@Descendente, 1) = 1 THEN N' DESC' ELSE N' ASC' END + N', i.IssueSk DESC';

    DECLARE @sql nvarchar(max) = N'SELECT ' + @select + N', COUNT(*) OVER () AS TotalFilas
        FROM rpt.vIssue i
        WHERE 1 = 1' + @where + N'
        ORDER BY ' + @orden + N'
        OFFSET (@p - 1) * @t ROWS FETCH NEXT @t ROWS ONLY
        OPTION (RECOMPILE);';
    EXEC sp_executesql @sql, N'@c nvarchar(max), @hoy date, @p int, @t int', @c = @Criterios, @hoy = @hoy, @p = @Pagina, @t = @TamanoPagina;
END;
GO
