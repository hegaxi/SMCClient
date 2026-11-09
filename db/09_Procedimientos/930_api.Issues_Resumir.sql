/* Resumen de una búsqueda avanzada calculado en SQL Server sobre TODOS los issues que cumplen los criterios
   (no solo una página): lo usan los widgets de barras e indicador de los tableros.
   @Criterios   los mismos de api.Issues_Consultar.
   @AgruparPor  clave de cualquier campo (vacío = un solo total). Fechas: por mes (aaaa-mm). Campos de varios valores
                (etiquetas, sprints…): un issue cuenta en cada uno de sus valores; sin valor = "(vacío)".
   @Agregacion  conteo | suma | promedio | maximo | minimo.   @Valor  campo numérico (obligatorio salvo en conteo).
   @Top         barras a devolver contando "Otros": @Top - 1 grupos y el resto juntos en "Otros" (cada issue una vez).
                Agrupado por fecha: los @Top periodos más recientes en orden cronológico, sin "Otros" (una tendencia).
   Horas en un periodo: si los criterios acotan la "Fecha de registro de tiempo" (registro_fecha) y se calculan horas
   (horas, horas_registradas, horas_automaticas), se suman solo los worklogs de ese periodo y cada uno una vez (los propios
   de cada issue); antes se sumaban todas las horas de la vida de cada issue con su árbol y un tablero de "últimos 30 días"
   mostraba hasta 3 veces más.
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

    -- Periodo de los worklogs (criterios sobre registro_fecha): las horas se acotan a él.
    DECLARE @pDesde date, @pHasta date;
    SELECT @pDesde = MAX(CASE WHEN c.Operador IN ('desde', 'entre') THEN COALESCE(dash.fn_FechaRelativa(c.Valor, @hoy), TRY_CONVERT(date, c.Valor)) END),
           @pHasta = MIN(CASE WHEN c.Operador = 'hasta' THEN COALESCE(dash.fn_FechaRelativa(c.Valor, @hoy), TRY_CONVERT(date, c.Valor))
                              WHEN c.Operador = 'entre' THEN COALESCE(dash.fn_FechaRelativa(c.Hasta, @hoy), TRY_CONVERT(date, c.Hasta)) END)
    FROM OPENJSON(@Criterios) WITH (Campo varchar(60) '$.campo', Operador varchar(20) '$.operador', Valor nvarchar(100) '$.valor', Hasta nvarchar(100) '$.hasta') c
    WHERE c.Campo = 'registro_fecha';
    IF @Agregacion <> 'conteo' AND (@pDesde IS NOT NULL OR @pHasta IS NOT NULL) AND @Valor IN ('horas', 'horas_registradas', 'horas_automaticas')
    BEGIN
        -- Solo los worklogs PROPIOS de cada issue: cada worklog pertenece a un solo issue, así no se repite aunque el
        -- filtro traiga la épica, sus tareas y sus subtareas (las que tienen registros en el periodo ya cumplen el filtro).
        DECLARE @ids nvarchar(max) = N'SELECT i.IssueId';
        DECLARE @origen nvarchar(200) = CASE @Valor
            WHEN 'horas_registradas' THEN N' AND COALESCE(w.EsAutomatico, 0) = 0'   -- las copias automáticas nunca se suman
            WHEN 'horas_automaticas' THEN N' AND w.EsAutomatico = 1 AND ISNULL(w.EsCopia, 0) = 0' ELSE N' AND ISNULL(w.EsCopia, 0) = 0' END;
        SET @exprValor = N'(SELECT CAST(SUM(CAST(w.Segundos AS bigint)) / 3600.0 AS decimal(19,4)) FROM ops.Worklog w
            WHERE w.FuenteId = i.FuenteId AND w.Eliminado = 0' + @origen + N'
              AND (@pd IS NULL OR CAST(w.Inicio AS date) >= @pd) AND (@ph IS NULL OR CAST(w.Inicio AS date) <= @ph)
              AND w.IssueId IN (' + @ids + N'))';
        SET @etqValor = CASE @Valor WHEN 'horas_automaticas' THEN N'Horas automáticas' WHEN 'horas_registradas' THEN N'Horas registradas por personas' ELSE N'Horas' END + N' en el periodo';
    END;

    -- Grupo.
    DECLARE @tipoG varchar(10), @exprG nvarchar(600), @multiG nvarchar(600), @etqG nvarchar(200);
    IF @AgruparPor IS NOT NULL
    BEGIN
        SELECT @tipoG = Tipo, @exprG = Expresion, @multiG = ExpresionMulti, @etqG = Etiqueta FROM rpt.fn_CamposBuscador() WHERE Clave = @AgruparPor;
        IF @tipoG IS NULL THROW 50400, 'Campo para agrupar desconocido.', 1;
    END;
    DECLARE @x nvarchar(max) = CASE WHEN @multiG IS NOT NULL THEN N'm.v' ELSE @exprG END;
    DECLARE @esFecha bit = CASE WHEN @tipoG = 'fecha' THEN 1 ELSE 0 END;
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
        rk AS (SELECT g, Valor, Issues, ' + CASE WHEN @esFecha = 1
               -- fechas: los periodos más recientes, todos como grupo (sin "Otros")
               THEN N'ROW_NUMBER() OVER (ORDER BY g DESC) AS n, CAST(0 AS int) AS total FROM grupos WHERE g IS NOT NULL'
               ELSE N'ROW_NUMBER() OVER (ORDER BY Valor DESC, Issues DESC, g) AS n, COUNT(*) OVER () AS total FROM grupos' END + N'),
        resto AS (SELECT DISTINCT b.IssueSk, b.v FROM base b JOIN rk ON EXISTS (SELECT b.g INTERSECT SELECT rk.g) WHERE rk.total > @top AND rk.n >= @top)
        SELECT ISNULL(g, CASE WHEN @agrupado = 1 THEN N''(vacío)'' END) AS Grupo, CAST(Valor AS decimal(19,4)) AS Valor, Issues,
               1 AS Grupos, CAST(0 AS bit) AS EsOtros, @etqG AS EtiquetaGrupo, @etqV AS EtiquetaValor, CASE WHEN @esFecha = 1 THEN CAST(ROW_NUMBER() OVER (ORDER BY g) AS int) ELSE n END AS Posicion
        FROM rk WHERE (rk.total <= @top OR rk.n < @top) AND (@esFecha = 0 OR rk.n <= @top)
        UNION ALL
        SELECT N''Otros'', CAST((SELECT ' + @agg + N' FROM resto) AS decimal(19,4)), (SELECT COUNT(*) FROM resto),
               (SELECT COUNT(*) FROM rk WHERE rk.n >= @top), CAST(1 AS bit), @etqG, @etqV, @top
        WHERE (SELECT MAX(total) FROM rk) > @top
        UNION ALL
        SELECT CAST(NULL AS nvarchar(400)), CAST(CASE WHEN @calc = ''conteo'' THEN 0 END AS decimal(19,4)), 0, 0, CAST(0 AS bit), @etqG, @etqV, 1
        WHERE @agrupado = 0 AND NOT EXISTS (SELECT 1 FROM rk)
        ORDER BY ' + CASE WHEN @esFecha = 1 THEN N'Grupo' ELSE N'Posicion' END + N'
        OPTION (RECOMPILE);';
    DECLARE @agrupado bit = CASE WHEN @AgruparPor IS NULL THEN 0 ELSE 1 END;
    EXEC sp_executesql @sql, N'@c nvarchar(max), @hoy date, @top int, @agrupado bit, @calc varchar(10), @etqG nvarchar(200), @etqV nvarchar(200), @esFecha bit, @pd date, @ph date',
         @c = @Criterios, @hoy = @hoy, @top = @Top, @agrupado = @agrupado, @calc = @Agregacion, @etqG = @etqG, @etqV = @etqValor,
         @esFecha = @esFecha, @pd = @pDesde, @ph = @pHasta;
END;
GO
