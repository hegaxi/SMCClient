/* Valida los criterios de la búsqueda avanzada y arma las condiciones (" AND ..."), para api.Issues_Consultar y
   api.Issues_Resumir: así la búsqueda y sus resúmenes filtran SIEMPRE igual.
   Las condiciones usan el alias i (rpt.vIssue) y leen cada valor del JSON @c dentro de la consulta (JSON_VALUE /
   OPENJSON con índices numéricos); los valores nunca se concatenan. El SQL que la ejecute debe declarar
   @c nvarchar(max) (los criterios) y @hoy date. Las expresiones salen solo de rpt.fn_CamposBuscador. */
CREATE OR ALTER PROCEDURE rpt.Buscador_Condiciones
    @Criterios nvarchar(max),
    @Hoy       date,
    @Where     nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF ISJSON(@Criterios) = 0 OR LEFT(LTRIM(@Criterios), 1) <> N'[' THROW 50400, 'Los criterios deben ser un arreglo JSON.', 1;
    DECLARE @msg nvarchar(1000);
    SELECT * INTO #cb FROM rpt.fn_CamposBuscador();

    SELECT CAST(j.[key] AS int) AS k, JSON_VALUE(j.value, '$.campo') AS Campo, JSON_VALUE(j.value, '$.operador') AS Operador,
           JSON_VALUE(j.value, '$.valor') AS Valor, JSON_VALUE(j.value, '$.hasta') AS Hasta,
           (SELECT COUNT(*) FROM OPENJSON(j.value, '$.valores')) AS NumValores
    INTO #crit
    FROM OPENJSON(@Criterios) j;

    IF (SELECT COUNT(*) FROM #crit) > 40 THROW 50400, 'Demasiados criterios (máximo 40).', 1;

    -- Validaciones (mensajes con el nombre del campo, para el usuario).
    SET @msg = (SELECT STRING_AGG(ISNULL(c.Campo, N'(sin campo)'), N', ') FROM #crit c WHERE NOT EXISTS (SELECT 1 FROM #cb f WHERE f.Clave = c.Campo));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Campos desconocidos: ' + @msg + N'.'; THROW 50400, @msg, 1; END;
    SET @msg = (SELECT STRING_AGG(CONCAT(f.Etiqueta, N' (', ISNULL(c.Operador, N'sin operador'), N')'), N', ')
                FROM #crit c JOIN #cb f ON f.Clave = c.Campo
                WHERE c.Operador IS NULL OR c.Operador NOT IN (SELECT value FROM STRING_SPLIT(f.Operadores, ',')));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Operador no válido para: ' + @msg + N'.'; THROW 50400, @msg, 1; END;
    SET @msg = (SELECT STRING_AGG(f.Etiqueta, N', ') FROM #crit c JOIN #cb f ON f.Clave = c.Campo
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
    SET @Where = N'';
    DECLARE @k int, @op varchar(20), @tipo varchar(10), @expr nvarchar(600), @multi nvarchar(600);
    DECLARE @x nvarchar(max), @v nvarchar(max), @h nvarchar(max), @lista nvarchar(max), @p nvarchar(max), @cond nvarchar(max);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.k, c.Operador, f.Tipo, f.Expresion, f.ExpresionMulti FROM #crit c JOIN #cb f ON f.Clave = c.Campo ORDER BY c.k;
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

        SET @Where += N' AND ' + @cond;
        FETCH c INTO @k, @op, @tipo, @expr, @multi;
    END;
    CLOSE c; DEALLOCATE c;
END;
GO
