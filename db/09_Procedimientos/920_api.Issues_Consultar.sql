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
    DECLARE @where nvarchar(max);
    EXEC rpt.Buscador_Condiciones @Criterios = @Criterios, @Hoy = @hoy, @Where = @where OUTPUT;

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
