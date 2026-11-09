/* Prueba de carga: tiempo de las consultas que usa la aplicación sobre los datos de 010_generar_datos.sql.
   Cada caso corre 4 veces: la primera incluye compilar el plan; se informa también la mediana de las otras 3.
   Presupuesto: 1 500 ms las consultas interactivas (búsqueda, detalle, estado) y 3 000 ms los reportes.
   Uso: sqlcmd -d SMCClient -I -i tests/carga/020_medir.sql -o salida.txt ; grep '^MEDICION' salida.txt
   Las líneas MEDICION|caso|primera_ms|mediana_ms|presupuesto_ms|resultado son el informe. */
SET NOCOUNT ON;
GO
DECLARE @casos TABLE (n int IDENTITY, Caso nvarchar(80), Sql nvarchar(max), Presupuesto int);
DECLARE @hoy date = CAST(SYSDATETIMEOFFSET() AS date);
DECLARE @mes nvarchar(10) = CONVERT(nvarchar(10), DATEADD(MONTH, -1, @hoy), 23), @anio nvarchar(10) = CONVERT(nvarchar(10), DATEADD(YEAR, -1, @hoy), 23), @h nvarchar(10) = CONVERT(nvarchar(10), @hoy, 23);
INSERT @casos (Caso, Sql, Presupuesto) VALUES
 (N'Sync_Estado (cada 5 s por usuario)',                  N'EXEC api.Sync_Estado @Detalle = 0', 1500),
 (N'Búsqueda: sin criterios, página 1',                   N'EXEC api.Issues_Consultar', 1500),
 (N'Búsqueda: proyecto + estado + texto',                 N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"proyecto","operador":"en","valores":["CSCR"]},{"campo":"categoria","operador":"no_en","valores":["Terminado"]},{"campo":"texto","operador":"contiene","valor":"inventario"}]''', 1500),
 (N'Búsqueda: columnas épica y horas, orden por horas',   N'EXEC api.Issues_Consultar @Columnas = N''resumen,epica,horas_registradas,horas_automaticas'', @OrdenarPor = ''horas_registradas''', 1500),
 (N'Búsqueda: tareas de una épica',                       N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"epica","operador":"en","valores":["CSCR-2 · Epic de carga 2"]}]'', @Columnas = N''resumen,horas_registradas''', 1500),
 (N'Búsqueda: horas registradas > 50',                    N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"horas_registradas","operador":"mayor","valor":"50"}]''', 1500),
 (N'Búsqueda: quién registró tiempo',                     N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"registro_persona","operador":"en","valores":["Persona 7"]}]''', 1500),
 (N'Búsqueda: SLA incumplido (mesa de ayuda)',            N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"sla_incumplido","operador":"es","valor":"1"}]''', 1500),
 (N'Valores para elegir: épicas',                         N'EXEC api.Issues_Valores @Campo = ''epica''', 1500),
 (N'Widget: conteo por estado',                           N'EXEC api.Issues_Resumir @AgruparPor = ''estado''', 3000),
 (N'Widget: horas registradas por épica',                 N'EXEC api.Issues_Resumir @AgruparPor = ''epica'', @Agregacion = ''suma'', @Valor = ''horas_registradas''', 3000),
 (N'Detalle de una épica (con su árbol)',                 N'EXEC api.Issue_Detalle @Clave = ''CSCR-2''', 1500),
 (N'Horas por persona: último mes',                       N'EXEC api.Horas_PorPersona @Desde = ''' + @mes + N''', @Hasta = ''' + @h + N'''', 3000),
 (N'Horas por persona: último año',                       N'EXEC api.Horas_PorPersona @Desde = ''' + @anio + N''', @Hasta = ''' + @h + N'''', 3000),
 (N'Horas por persona: una épica, último año',            N'EXEC api.Horas_PorPersona @Desde = ''' + @anio + N''', @Hasta = ''' + @h + N''', @Epica = ''CSCR-2''', 3000),
 (N'Horas por sprint (todos)',                            N'EXEC api.Horas_PorSprint @Proyecto = ''CSCR''', 3000),
 (N'Avance de sprints',                                   N'EXEC api.Sprint_Avance @Proyecto = ''CSCR''', 3000),
 (N'Avance de épicas',                                    N'EXEC api.Epicas_Avance', 3000),
 (N'Estimado vs. real (tareas)',                          N'EXEC api.Estimacion_VsReal', 3000);

DECLARE @i int = 1, @k int, @caso nvarchar(80), @sql nvarchar(max), @pres int, @t0 datetime2, @ms int, @primera int;
DECLARE @t TABLE (ms int);
WHILE @i <= (SELECT MAX(n) FROM @casos)
BEGIN
    SELECT @caso = Caso, @sql = Sql, @pres = Presupuesto FROM @casos WHERE n = @i;
    DELETE @t; SET @k = 1;
    WHILE @k <= 4
    BEGIN
        IF @k = 1 EXEC sp_recompile N'api.Issues_Consultar';   -- la primera vuelta mide también la compilación
        SET @t0 = SYSDATETIME();
        EXEC (@sql);
        SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
        IF @k = 1 SET @primera = @ms ELSE INSERT @t VALUES (@ms);
        SET @k += 1;
    END;
    SET @ms = (SELECT ms FROM (SELECT ms, ROW_NUMBER() OVER (ORDER BY ms) AS r FROM @t) x WHERE r = 2);
    PRINT CONCAT(N'MEDICION|', @caso, N'|', @primera, N'|', @ms, N'|', @pres, N'|', CASE WHEN @ms <= @pres THEN N'ok' ELSE N'EXCEDE' END);
    SET @i += 1;
END;
GO
