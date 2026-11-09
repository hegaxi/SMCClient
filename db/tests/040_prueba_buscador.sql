/* Búsqueda avanzada (api.Issues_Consultar): campos, operadores, columnas, orden, paginación, campos personalizados,
   fechas relativas, guardado como filtro y resistencia a inyección.
   Ejecutar después de 010 (usa sus issues MDA-1 y SCR-7):  sqlcmd -b -I -x -d SMCClient -i tests/040_prueba_buscador.sql */
SET NOCOUNT ON;
SET ANSI_WARNINGS ON;
GO
IF SCHEMA_ID('prueba') IS NULL EXEC ('CREATE SCHEMA prueba');
GO
CREATE OR ALTER PROCEDURE prueba.Afirmar @Condicion bit, @Mensaje nvarchar(400)
AS
BEGIN
    IF ISNULL(@Condicion, 0) = 0 BEGIN DECLARE @m nvarchar(500) = N'FALLÓ: ' + @Mensaje; THROW 50999, @m, 1; END;
    PRINT N'ok  ' + @Mensaje;
END;
GO
CREATE OR ALTER PROCEDURE prueba.AfirmarError @Sql nvarchar(max), @Numero int, @Mensaje nvarchar(400)
AS
BEGIN
    DECLARE @n int = 0, @texto nvarchar(4000);
    BEGIN TRY EXEC sp_executesql @Sql; END TRY
    BEGIN CATCH SELECT @n = ERROR_NUMBER(), @texto = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK; END CATCH;
    DECLARE @ok bit = CASE WHEN @n = @Numero THEN 1 ELSE 0 END;
    DECLARE @m nvarchar(800) = CONCAT(@Mensaje, CASE WHEN @ok = 0 THEN CONCAT(N' (error ', @n, N': ', @texto, N')') ELSE N'' END);
    EXEC prueba.Afirmar @ok, @m;
END;
GO
/* Devuelve las claves (separadas por coma, en orden) y el total que encuentra una búsqueda. */
CREATE OR ALTER PROCEDURE prueba.Buscar @Criterios nvarchar(max), @Claves nvarchar(400) OUTPUT, @Total int = NULL OUTPUT,
    @OrdenarPor varchar(60) = NULL, @Descendente bit = 1, @Pagina int = 1, @TamanoPagina int = 50, @Filas int = NULL OUTPUT
AS
BEGIN
    DECLARE @r TABLE (n int IDENTITY, Clave nvarchar(50), TotalFilas int);
    INSERT @r (Clave, TotalFilas) EXEC api.Issues_Consultar @Criterios = @Criterios, @Columnas = N'clave', @OrdenarPor = @OrdenarPor,
         @Descendente = @Descendente, @Pagina = @Pagina, @TamanoPagina = @TamanoPagina;
    SELECT @Claves = ISNULL(STRING_AGG(CAST(Clave AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY n), N''), @Total = ISNULL(MAX(TotalFilas), 0), @Filas = COUNT(*) FROM @r;
END;
GO

/* ===== Catálogo de campos ===== */
DECLARE @ok bit;
DECLARE @c TABLE (Clave varchar(60), Etiqueta nvarchar(200), Tipo varchar(10), Origen nvarchar(20), Multivalor bit, EsColumna bit,
                  ColumnaPredeterminada bit, Operadores varchar(200), Alias nvarchar(100));
INSERT @c EXEC api.Issues_Campos;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @c WHERE Clave = 'estado' AND Tipo = 'lista' AND Operadores LIKE '%no_en%')
                AND EXISTS (SELECT 1 FROM @c WHERE Clave = 'creado' AND Tipo = 'fecha')
                AND EXISTS (SELECT 1 FROM @c WHERE Clave = 'etiquetas' AND Multivalor = 1)
                AND EXISTS (SELECT 1 FROM @c WHERE Clave = 'cf:customfield_10468' AND Origen = N'Personalizado' AND Etiqueta = N'Estación')
           THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Campos estándar y personalizados de Jira, con tipo y operadores';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @c WHERE Clave IN ('cf:customfield_10020', 'cf:customfield_10099', 'cf:customfield_10010')) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Los personalizados que ya alimentan un campo estándar (sprint, story points, tipo de solicitud) no se repiten';

DECLARE @v TABLE (Valor nvarchar(400), Issues int);
INSERT @v EXEC api.Issues_Valores @Campo = 'cf:customfield_10468';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @v) = 2 AND EXISTS (SELECT 1 FROM @v WHERE Valor = N'ESTACIÓN SUR' AND Issues = 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Valores de un campo personalizado de lista, con su número de issues';
DELETE @v; INSERT @v EXEC api.Issues_Valores @Campo = 'estado', @Texto = N'prog';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @v) = 1 AND (SELECT Valor FROM @v) = N'In Progress' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Valores filtrados por texto';
EXEC prueba.AfirmarError N'EXEC api.Issues_Valores @Campo = ''creado'';', 50400, N'Un campo de fecha no tiene lista de valores';
EXEC prueba.AfirmarError N'EXEC api.Issues_Valores @Campo = ''nada'';', 50404, N'Campo inexistente';
GO

/* ===== Criterios ===== */
DECLARE @ok bit, @k nvarchar(400), @t int;
EXEC prueba.Buscar N'[]', @k OUTPUT, @t OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7,MDA-1' AND @t = 2 THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Sin criterios: todo, del más reciente al más antiguo (actualizado)';
EXEC prueba.Buscar N'[{"campo":"estado","operador":"no_en","valores":["Done"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Lista: no en';
EXEC prueba.Buscar N'[{"campo":"proyecto","operador":"en","valores":["MDA","SCR"]},{"campo":"tipo","operador":"en","valores":["Historia"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Varios criterios se combinan con Y';
EXEC prueba.Buscar N'[{"campo":"resolucion","operador":"vacio"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7,MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Vacío';
EXEC prueba.Buscar N'[{"campo":"padre","operador":"no_vacio"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'No vacío';
EXEC prueba.Buscar N'[{"campo":"texto","operador":"contiene","valor":"entrar"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Texto libre: contiene';
EXEC prueba.Buscar N'[{"campo":"resumen","operador":"no_contiene","valor":"entrar"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Texto: no contiene';
EXEC prueba.Buscar N'[{"campo":"story_points","operador":"mayor_igual","valor":"8"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Número: mayor o igual';
EXEC prueba.Buscar N'[{"campo":"horas","operador":"entre","valor":"2","hasta":"4"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Número: entre (horas invertidas)';
EXEC prueba.Buscar N'[{"campo":"creado","operador":"entre","valor":"2026-10-01","hasta":"2026-10-01"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Fecha: entre incluye el día completo';
EXEC prueba.Buscar N'[{"campo":"creado","operador":"desde","valor":"{inicio_anio}"},{"campo":"creado","operador":"hasta","valor":"{hoy+3650}"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7,MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Fecha relativa ({inicio_anio}, {hoy+N})';
EXEC prueba.Buscar N'[{"campo":"abierto","operador":"es","valor":"1"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Sí/no';
EXEC prueba.Buscar N'[{"campo":"sla_incumplido","operador":"es","valor":"1"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'SLA incumplido';
EXEC prueba.Buscar N'[{"campo":"etiquetas","operador":"en","valores":["urgente"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Multivalor: en (etiquetas)';
EXEC prueba.Buscar N'[{"campo":"etiquetas","operador":"no_en","valores":["urgente"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Multivalor: no en incluye a los que no tienen ninguna';
EXEC prueba.Buscar N'[{"campo":"sprint","operador":"en","valores":["Sprint 4"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Sprint';
EXEC prueba.Buscar N'[{"campo":"cf:customfield_10468","operador":"en","valores":["ESTACIÓN SUR"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Campo personalizado de Jira';
GO

/* ===== Columnas, orden y paginación ===== */
DECLARE @ok bit, @k nvarchar(400), @t int;
DECLARE @r TABLE (Clave nvarchar(50), Sprint nvarchar(400), Estacion nvarchar(400), Resumen nvarchar(400), TotalFilas int);
INSERT @r EXEC api.Issues_Consultar @Columnas = N'sprint, cf:customfield_10468, resumen, clave', @OrdenarPor = 'clave', @Descendente = 0;
SET @ok = CASE WHEN (SELECT Sprint FROM @r WHERE Clave = N'SCR-7') = N'Sprint 3, Sprint 4'
                AND (SELECT Estacion FROM @r WHERE Clave = N'MDA-1') LIKE N'ESTACIÓN%, ESTACIÓN%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Columnas en el orden pedido (la clave primero, sin repetirla); multivalor separados por coma';
EXEC prueba.Buscar N'[]', @k OUTPUT, @OrdenarPor = 'clave', @Descendente = 0;
SET @ok = CASE WHEN @k = N'MDA-1,SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Orden ascendente por clave';
EXEC prueba.Buscar N'[]', @k OUTPUT, @t OUTPUT, @OrdenarPor = 'clave', @Descendente = 0, @Pagina = 2, @TamanoPagina = 1;
SET @ok = CASE WHEN @k = N'SCR-7' AND @t = 2 THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Paginación con total de filas';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @OrdenarPor = ''etiquetas'';', 50400, N'No se ordena por un campo multivalor';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Columnas = N''resumen,texto'';', 50400, N'Un campo que no es columna no se muestra';
GO

/* ===== Validación y seguridad ===== */
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Criterios = N''{"campo":"estado"}'';', 50400, N'Los criterios deben ser un arreglo';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"estado","operador":"mayor","valor":"1"}]'';', 50400, N'Operador que no corresponde al tipo';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"estado","operador":"en","valores":[]}]'';', 50400, N'"En" sin valores';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"creado","operador":"desde","valor":"ayer"}]'';', 50400, N'Fecha inválida';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"horas","operador":"entre","valor":"1"}]'';', 50400, N'"Entre" sin el segundo valor';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Criterios = N''[{"campo":"i.Clave = 1; DROP TABLE ops.Issue --","operador":"igual","valor":"1"}]'';', 50400, N'Inyección en el nombre del campo: rechazada';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @Columnas = N''resumen,i.Clave FROM sys.objects--'';', 50400, N'Inyección en las columnas: rechazada';
EXEC prueba.AfirmarError N'EXEC api.Issues_Consultar @OrdenarPor = ''clave; DROP TABLE x'';', 50400, N'Inyección en el orden: rechazada';
DECLARE @k nvarchar(400), @ok bit;
EXEC prueba.Buscar N'[{"campo":"resumen","operador":"contiene","valor":"'') OR 1=1 --"},{"campo":"estado","operador":"en","valores":["x'') OR (1=1"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'' AND OBJECT_ID('ops.Issue') IS NOT NULL THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Inyección en los valores: se trata como texto (no encuentra nada)';
GO

/* ===== Como filtro guardado (para tableros) ===== */
DECLARE @ok bit;
DECLARE @id TABLE (Id int);
IF NOT EXISTS (SELECT 1 FROM seg.Usuario WHERE Login = N'buscadora')
BEGIN
    DECLARE @t TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
    IF NOT EXISTS (SELECT 1 FROM seg.Usuario) EXEC seg.Instalacion_CrearAdministrador @Login = N'jefe', @Nombre = N'Jefa', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12;
    DECLARE @admin nvarchar(200) = (SELECT TOP (1) u.Login FROM seg.Usuario u WHERE u.Activo = 1 AND seg.fn_EsAdministrador(u.UsuarioId) = 1);
    INSERT @t EXEC api.Usuario_Guardar @Login = N'buscadora', @Nombre = N'Buscadora', @Roles = N'Consulta', @UsuarioActual = @admin;
END;
INSERT @id EXEC api.Filtro_Guardar @Nombre = N'Abiertos recientes', @Procedimiento = N'Issues_Consultar',
     @Parametros = N'{"Criterios":"[{\"campo\":\"abierto\",\"operador\":\"es\",\"valor\":\"1\"},{\"campo\":\"creado\",\"operador\":\"desde\",\"valor\":\"{inicio_anio}\"}]","Columnas":"resumen,estado"}',
     @UsuarioActual = N'buscadora';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM dash.Filtro WHERE FiltroId = (SELECT Id FROM @id) AND Procedimiento = N'Issues_Consultar') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Una búsqueda avanzada se guarda como filtro (usable en widgets)';
DECLARE @p nvarchar(max) = (SELECT dash.fn_ResolverParametros(Parametros, '2026-11-08') FROM dash.Filtro WHERE FiltroId = (SELECT Id FROM @id));
SET @ok = CASE WHEN JSON_VALUE(@p, '$.Criterios') LIKE N'%{inicio_anio}%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Las fechas relativas dentro de los criterios se conservan (las resuelve la búsqueda al ejecutarse)';
DECLARE @crit nvarchar(max) = JSON_VALUE(@p, '$.Criterios'), @k nvarchar(400);
EXEC prueba.Buscar @crit, @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'El filtro guardado devuelve lo esperado';
GO

/* ===== Resumen en SQL (para widgets): sobre TODOS los issues, sin tope de filas ===== */
DECLARE @ok bit;
DECLARE @r TABLE (Grupo nvarchar(400), Valor decimal(19,4), Issues int, Grupos int, EsOtros bit, EtiquetaGrupo nvarchar(200), EtiquetaValor nvarchar(200), Posicion int);
INSERT @r EXEC api.Issues_Resumir @AgruparPor = 'proyecto', @Agregacion = 'suma', @Valor = 'horas';
SET @ok = CASE WHEN (SELECT Valor FROM @r WHERE Grupo = N'SCR') = 8 AND (SELECT Valor FROM @r WHERE Grupo = N'MDA') = 3
                AND (SELECT TOP (1) EtiquetaValor FROM @r) = N'Horas invertidas (Jira)' AND (SELECT TOP (1) Grupo FROM @r ORDER BY Posicion) = N'SCR' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Suma por grupo, de mayor a menor, con las etiquetas de los campos';
DELETE @r; INSERT @r EXEC api.Issues_Resumir @AgruparPor = 'etiquetas';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @r) = 3 AND (SELECT Issues FROM @r WHERE Grupo = N'(vacío)') = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Campo de varios valores: un issue cuenta en cada valor; sin valor = (vacío)';
DELETE @r; INSERT @r EXEC api.Issues_Resumir @AgruparPor = 'etiquetas', @Top = 2;
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @r) = 2 AND (SELECT Issues FROM @r WHERE EsOtros = 1) = 1 AND (SELECT Grupos FROM @r WHERE EsOtros = 1) = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'"Otros" junta el resto contando cada issue una sola vez';
DELETE @r; INSERT @r EXEC api.Issues_Resumir @AgruparPor = 'creado', @Agregacion = 'promedio', @Valor = 'horas';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @r) = 1 AND (SELECT Grupo FROM @r) = N'2026-10' AND (SELECT Valor FROM @r) = 5.5 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Fechas agrupadas por mes; promedio';
DELETE @r; INSERT @r EXEC api.Issues_Resumir @Criterios = N'[{"campo":"estado","operador":"en","valores":["nada"]}]';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @r) = 1 AND (SELECT Valor FROM @r) = 0 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Sin issues: el conteo es 0 (un renglón)';
EXEC prueba.AfirmarError N'EXEC api.Issues_Resumir @Agregacion = ''suma'', @Valor = ''estado'';', 50400, N'Solo se suman campos numéricos';
EXEC prueba.AfirmarError N'EXEC api.Issues_Resumir @Agregacion = ''suma'';', 50400, N'Suma sin campo';
EXEC prueba.AfirmarError N'EXEC api.Issues_Resumir @AgruparPor = ''i.Clave); DROP TABLE x --'';', 50400, N'Inyección en el campo para agrupar: rechazada';
EXEC prueba.AfirmarError N'EXEC api.Issues_Resumir @Agregacion = ''COUNT(*)--'';', 50400, N'Inyección en el cálculo: rechazada';
EXEC prueba.AfirmarError N'EXEC api.Issues_Resumir @Criterios = N''[{"campo":"x","operador":"en","valores":["a"]}]'';', 50400, N'Los criterios se validan igual que en la búsqueda';
GO

/* 1 200 issues de carga (en una transacción que se deshace): la página llega a 500, el resumen cuenta todos. */
BEGIN TRANSACTION;
DECLARE @ok bit, @k nvarchar(400), @t int, @filas int;
WITH n AS (SELECT TOP (1200) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_columns a CROSS JOIN sys.all_columns b)
INSERT ops.Issue (FuenteId, IssueId, Clave, ProyectoId, TipoIssueId, TipoIssue, EstadoId, CategoriaEstado, PrioridadId, Prioridad,
                  ResponsableId, Resumen, TiempoInvertidoSeg, Creado, Actualizado)
SELECT i.FuenteId, CONCAT('9', n.n), CONCAT('MDA-', 1000 + n.n), i.ProyectoId, i.TipoIssueId, i.TipoIssue,
       CASE WHEN n.n % 3 = 0 THEN 10001 ELSE i.EstadoId END, CASE WHEN n.n % 3 = 0 THEN 'done' ELSE i.CategoriaEstado END,
       i.PrioridadId, i.Prioridad, i.ResponsableId, N'Carga de prueba', 1800, i.Creado, i.Actualizado
FROM n CROSS JOIN ops.Issue i WHERE i.Clave = 'MDA-1';
DECLARE @crit nvarchar(200) = N'[{"campo":"resumen","operador":"igual","valor":"Carga de prueba"}]';
EXEC prueba.Buscar @crit, @k OUTPUT, @t OUTPUT, @TamanoPagina = 500, @Filas = @filas OUTPUT;
SET @ok = CASE WHEN @t = 1200 AND @filas = 500 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Búsqueda de 1 200 issues: página de 500 con el total real';
DECLARE @r TABLE (Grupo nvarchar(400), Valor decimal(19,4), Issues int, Grupos int, EsOtros bit, EtiquetaGrupo nvarchar(200), EtiquetaValor nvarchar(200), Posicion int);
INSERT @r EXEC api.Issues_Resumir @Criterios = @crit, @Agregacion = 'suma', @Valor = 'horas';
SET @ok = CASE WHEN (SELECT Valor FROM @r) = 600 AND (SELECT Issues FROM @r) = 1200 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Resumen sin tope: 1 200 issues x 0.5 h = 600 h (no las 250 h de una página)';
DELETE @r; INSERT @r EXEC api.Issues_Resumir @Criterios = @crit, @AgruparPor = 'categoria';
SET @ok = CASE WHEN (SELECT Valor FROM @r WHERE Grupo = N'En curso') = 800 AND (SELECT Valor FROM @r WHERE Grupo = N'Terminado') = 400 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Conteo por grupo sobre los 1 200';
ROLLBACK;
GO

/* ===== Widgets con una búsqueda avanzada ===== */
DECLARE @ok bit, @sql nvarchar(max);
DECLARE @id TABLE (Id int);
DECLARE @f int = (SELECT FiltroId FROM dash.Filtro WHERE Nombre = N'Abiertos recientes');
INSERT @id EXEC api.Tablero_Guardar @Nombre = N'Búsquedas', @UsuarioActual = N'buscadora';
DECLARE @tab int = (SELECT TOP (1) Id FROM @id);
DELETE @id; INSERT @id EXEC api.Widget_Guardar @TableroId = @tab, @Titulo = N'Por estado', @FiltroId = @f, @Tipo = 'barras',
     @Configuracion = N'{"etiqueta":"estado","agregacion":"conteo","limite":10}', @UsuarioActual = N'buscadora';
DELETE @id; INSERT @id EXEC api.Widget_Guardar @TableroId = @tab, @Titulo = N'Horas', @FiltroId = @f, @Tipo = 'indicador',
     @Configuracion = N'{"agregacion":"suma","columna":"horas"}', @UsuarioActual = N'buscadora';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM dash.Widget WHERE TableroId = @tab) = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Barras que cuentan por campo e indicador con suma sobre una búsqueda avanzada';
SET @sql = CONCAT(N'EXEC api.Widget_Guardar @TableroId = ', @tab, N', @Titulo = N''x'', @FiltroId = ', @f, N', @Tipo = ''barras'', @Configuracion = N''{"etiqueta":"NoExiste","agregacion":"conteo"}'', @UsuarioActual = N''buscadora'';');
EXEC prueba.AfirmarError @sql, 50400, N'Campo para agrupar inexistente rechazado';
SET @sql = CONCAT(N'EXEC api.Widget_Guardar @TableroId = ', @tab, N', @Titulo = N''x'', @FiltroId = ', @f, N', @Tipo = ''indicador'', @Configuracion = N''{"agregacion":"suma","columna":"estado"}'', @UsuarioActual = N''buscadora'';');
EXEC prueba.AfirmarError @sql, 50400, N'Suma de un campo no numérico rechazada';
SET @sql = CONCAT(N'EXEC api.Widget_Guardar @TableroId = ', @tab, N', @Titulo = N''x'', @FiltroId = ', @f, N', @Tipo = ''barras'', @Configuracion = N''{"etiqueta":"estado"}'', @UsuarioActual = N''buscadora'';');
EXEC prueba.AfirmarError @sql, 50400, N'Barras que suman necesitan el campo de valor';
GO

DROP PROCEDURE prueba.Buscar; DROP PROCEDURE prueba.AfirmarError; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DEL BUSCADOR PASARON';
GO
