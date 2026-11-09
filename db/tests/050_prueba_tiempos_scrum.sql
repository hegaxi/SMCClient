/* Tiempo reportado en Scrum: épicas, subtareas (donde las personas registran el tiempo), horas de una historia o
   épica con todos sus descendientes, horas por sprint (dentro de las fechas del sprint, sin repetir) y criterios de búsqueda por worklog.
   Ejecutar después de 010 (usa SCR-7, sus sprints y la fuente "prueba"). Los datos que agrega se borran al final. */
SET NOCOUNT ON;
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
CREATE OR ALTER PROCEDURE prueba.Correr @Entidad varchar(40), @Modo varchar(20), @Docs sync.DocumentoTipo READONLY
AS
BEGIN
    DECLARE @ej bigint, @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
    EXEC sync.Ejecucion_Iniciar @Fuente = 'prueba', @Entidad = @Entidad, @Modo = @Modo, @Propietario = N'worker-1', @EjecucionId = @ej OUTPUT;
    EXEC sync.Documento_Cargar @EjecucionId = @ej, @Documentos = @Docs;
    EXEC sync.Procesar_Pendientes @FuenteId = @f, @EjecucionId = @ej, @Entidad = @Entidad;
    EXEC sync.Ejecucion_Finalizar @EjecucionId = @ej, @Estado = 'ok';
END;
GO
CREATE OR ALTER PROCEDURE prueba.Claves @Criterios nvarchar(max), @Claves nvarchar(400) OUTPUT
AS
BEGIN
    DECLARE @r TABLE (n int IDENTITY, Clave nvarchar(50), TotalFilas int);
    INSERT @r (Clave, TotalFilas) EXEC api.Issues_Consultar @Criterios = @Criterios, @Columnas = N'clave', @OrdenarPor = 'clave', @Descendente = 0;
    SELECT @Claves = ISNULL(STRING_AGG(Clave, N',') WITHIN GROUP (ORDER BY n), N'') FROM @r;
END;
GO

/* ===== Datos: subtarea SCR-8 de la historia SCR-7 (en el Sprint 4, como la pone Jira) y sus worklogs ===== */
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Actualizado, Json) VALUES
 ('5010', '2026-11-03T12:00:00-06:00', N'{"id":"5010","key":"SCR-8","fields":{
    "summary":"Subtarea: consulta de reportes","project":{"id":"901","key":"SCR"},"issuetype":{"id":"10003","name":"Subtarea","subtask":true,"hierarchyLevel":-1},
    "status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},"priority":{"id":"3","name":"Medium"},
    "assignee":{"accountId":"dev-2","displayName":"Dev Dos","accountType":"atlassian","active":true},
    "created":"2026-10-17T08:00:00.000-0600","updated":"2026-11-03T12:00:00.000-0600","timespent":21600,"parent":{"id":"5002","key":"SCR-7"},
    "customfield_10020":[{"id":991,"name":"Sprint 4","state":"active","boardId":540,"startDate":"2026-10-16T11:00:00.000Z","endDate":"2026-10-30T05:30:00.000Z"}]}}');
INSERT @d (IdExterno, Actualizado, Json) VALUES
 ('4999', '2026-11-03T12:00:00-06:00', N'{"id":"4999","key":"SCR-1","fields":{
    "summary":"Épica: reportes","project":{"id":"901","key":"SCR"},"issuetype":{"id":"10000","name":"Epic","subtask":false,"hierarchyLevel":1},
    "status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},"priority":{"id":"3","name":"Medium"},
    "assignee":{"accountId":"dev-1","displayName":"Dev Uno","accountType":"atlassian","active":true},
    "created":"2026-09-01T08:00:00.000-0600","updated":"2026-11-03T12:00:00.000-0600"}}'),
 ('5011', '2026-11-03T12:00:00-06:00', N'{"id":"5011","key":"SCR-9","fields":{
    "summary":"Tarea: exportar a Excel","project":{"id":"901","key":"SCR"},"issuetype":{"id":"10007","name":"Task","subtask":false,"hierarchyLevel":0},
    "status":{"id":"1","name":"To Do","statusCategory":{"key":"new"}},"priority":{"id":"3","name":"Medium"},
    "assignee":{"accountId":"dev-2","displayName":"Dev Dos","accountType":"atlassian","active":true},
    "created":"2026-10-20T08:00:00.000-0600","updated":"2026-11-03T12:00:00.000-0600","timeoriginalestimate":36000,
    "parent":{"id":"4999","key":"SCR-1"},"customfield_10099":3}}');
EXEC prueba.Correr 'issue', 'incremental', @d;
DELETE @d;
INSERT @d (IdExterno, Actualizado, Json) VALUES
 ('7010', '2026-11-03T12:00:00-06:00', N'{"id":"7010","issueId":"5010","author":{"accountId":"dev-2","displayName":"Dev Dos","accountType":"atlassian"},"started":"2026-10-22T10:00:00.000-0600","timeSpentSeconds":14400}'),
 ('7011', '2026-11-03T12:00:00-06:00', N'{"id":"7011","issueId":"5002","author":{"accountId":"557058:automation","displayName":"Automation for Jira","accountType":"app"},"started":"2026-10-21T08:00:00.000-0600","timeSpentSeconds":28800}'),
 ('7012', '2026-11-03T12:00:00-06:00', N'{"id":"7012","issueId":"5010","author":{"accountId":"dev-2","displayName":"Dev Dos","accountType":"atlassian"},"started":"2026-11-03T10:00:00.000-0600","timeSpentSeconds":7200}'),
 ('7013', '2026-11-03T12:00:00-06:00', N'{"id":"7013","issueId":"4999","author":{"accountId":"557058:automation","displayName":"Automation for Jira","accountType":"app"},"started":"2026-10-23T08:00:00.000-0600","timeSpentSeconds":28800}'),
 ('7014', '2026-11-03T12:00:00-06:00', N'{"id":"7014","issueId":"5011","author":{"accountId":"dev-2","displayName":"Dev Dos","accountType":"atlassian"},"started":"2026-10-24T10:00:00.000-0600","timeSpentSeconds":10800}');
EXEC prueba.Correr 'worklog', 'incremental', @d;
GO

/* ===== Subtareas y horas de un issue con sus subtareas ===== */
DECLARE @ok bit, @k nvarchar(400);
SET @ok = (SELECT CASE WHEN MAX(CASE WHEN Clave = 'SCR-8' THEN CAST(EsSubtarea AS int) END) = 1
                        AND MAX(CASE WHEN Clave = 'SCR-7' THEN CAST(EsSubtarea AS int) END) = 0 THEN 1 ELSE 0 END FROM ops.Issue);
EXEC prueba.Afirmar @ok, N'La sincronización marca las subtareas (issuetype.subtask)';

DECLARE @r TABLE (Clave nvarchar(50), Reg decimal(12,2), Aut decimal(12,2), Jira decimal(12,2), TotalFilas int);
INSERT @r EXEC api.Issues_Consultar @Columnas = N'horas_registradas,horas_automaticas,horas',
     @Criterios = N'[{"campo":"proyecto","operador":"en","valores":["SCR"]}]', @OrdenarPor = 'clave', @Descendente = 0;
SET @ok = CASE WHEN (SELECT Reg FROM @r WHERE Clave = N'SCR-7') = 14 AND (SELECT Aut FROM @r WHERE Clave = N'SCR-7') = 8
                AND (SELECT Jira FROM @r WHERE Clave = N'SCR-7') = 8
                AND (SELECT Reg FROM @r WHERE Clave = N'SCR-8') = 6 AND (SELECT Aut FROM @r WHERE Clave = N'SCR-8') IS NULL THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'La historia suma lo registrado en su subtarea (8 + 6 = 14 h) y separa las automáticas (8 h); el campo de Jira solo trae lo propio';

EXEC prueba.Claves N'[{"campo":"proyecto","operador":"en","valores":["SCR"]},{"campo":"es_subtarea","operador":"es","valor":"0"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-1,SCR-7,SCR-9' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Criterio: sin subtareas';
GO
DECLARE @ok bit, @k nvarchar(400);
EXEC prueba.Claves N'[{"campo":"registro_persona","operador":"en","valores":["Dev Dos"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-8,SCR-9' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Criterio: quién registró tiempo (como worklogAuthor)';
EXEC prueba.Claves N'[{"campo":"registro_fecha","operador":"desde","valor":"2026-11-01"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-8' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Criterio: cuándo se registró tiempo (como worklogDate)';
EXEC prueba.Claves N'[{"campo":"horas_registradas","operador":"mayor","valor":"10"}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-1,SCR-7' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Criterio: horas registradas con hijos (la épica 17 h, la historia 14 h)';
DECLARE @v TABLE (Valor nvarchar(400), Issues int);
INSERT @v EXEC api.Issues_Valores @Campo = 'registro_persona';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @v WHERE Valor = N'Dev Dos' AND Issues = 2) AND NOT EXISTS (SELECT 1 FROM @v WHERE Valor = N'Automation for Jira') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Personas que registraron tiempo (sin la cuenta de Automation)';
GO

/* ===== Épicas ===== */
DECLARE @ok bit, @k nvarchar(400);
SET @ok = (SELECT CASE WHEN SUM(CASE WHEN Clave = 'SCR-1' AND NivelJerarquia = 1 THEN 1 END) = 1
                        AND SUM(CASE WHEN Clave = 'SCR-8' AND NivelJerarquia = -1 THEN 1 END) = 1
                        AND SUM(CASE WHEN Clave IN ('SCR-7', 'SCR-9') AND NivelJerarquia = 0 THEN 1 END) = 2 THEN 1 ELSE 0 END FROM ops.Issue);
EXEC prueba.Afirmar @ok, N'Nivel de jerarquía: épica 1, tareas 0, subtarea -1 (SCR-7 no lo trae y queda en 0)';

DECLARE @r TABLE (Clave nvarchar(50), Epica nvarchar(220), Nivel nvarchar(20), TotalFilas int);
INSERT @r EXEC api.Issues_Consultar @Columnas = N'epica,jerarquia', @OrdenarPor = 'clave', @Descendente = 0;
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @r WHERE Epica = N'SCR-1 · Épica: reportes') = 4
                AND (SELECT Epica FROM @r WHERE Clave = N'MDA-1') IS NULL
                AND (SELECT Nivel FROM @r WHERE Clave = N'SCR-1') = N'Épica' AND (SELECT Nivel FROM @r WHERE Clave = N'SCR-8') = N'Subtarea' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Columna Épica: la épica, sus tareas y la subtarea (por su tarea) la muestran; un ticket sin épica no';
EXEC prueba.Claves N'[{"campo":"epica","operador":"en","valores":["SCR-1 · Épica: reportes"]},{"campo":"jerarquia","operador":"en","valores":["Estándar"]}]', @k OUTPUT;
SET @ok = CASE WHEN @k = N'SCR-7,SCR-9' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Criterio: tareas de una épica (como parent = SCR-1)';
DECLARE @v TABLE (Valor nvarchar(400), Issues int);
INSERT @v EXEC api.Issues_Valores @Campo = 'epica';
SET @ok = CASE WHEN (SELECT Issues FROM @v WHERE Valor = N'SCR-1 · Épica: reportes') = 4 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Épicas para elegir, con cuántos issues tiene cada una';

DECLARE @e TABLE (Epica varchar(50), Resumen nvarchar(1000), Proyecto varchar(50), Estado nvarchar(100), Categoria varchar(20), Responsable nvarchar(200),
                  Issues int, Terminados int, Avance decimal(5,1), SP decimal(9,2), SPT decimal(9,2),
                  Est decimal(12,2), Reg decimal(12,2), Aut decimal(12,2), Ultimo datetimeoffset, Creado datetimeoffset, Venc date, Resuelto datetimeoffset,
                  Desv decimal(12,2), Consumo decimal(9,1), SinEst int);
INSERT @e EXEC api.Epicas_Avance @Proyecto = 'SCR';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @e) = 1 AND (SELECT Issues FROM @e) = 2 AND (SELECT Terminados FROM @e) = 1 AND (SELECT Avance FROM @e) = 50
                AND (SELECT SP FROM @e) = 11 AND (SELECT SPT FROM @e) = 8 AND (SELECT Est FROM @e) = 10 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Avance de la épica: 2 tareas, 1 terminada (50 %), 11 story points (8 terminados), 10 h estimadas';
SET @ok = CASE WHEN (SELECT Reg FROM @e) = 17 AND (SELECT Aut FROM @e) = 16 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas de la épica con todo su árbol: 17 h registradas (8 + 4 + 2 + 3, casi todas en tareas y subtarea) y 16 automáticas (8 en la épica + 8 en la historia)';
SET @ok = CASE WHEN (SELECT Desv FROM @e) = 7 AND (SELECT Consumo FROM @e) = 170 AND (SELECT SinEst FROM @e) = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Épica: 17 h registradas contra 10 estimadas (+7 h, 170 %) y 1 tarea sin estimar';

/* Estimado vs. real */
DECLARE @res TABLE (Issues int, Con int, Sin int, PctCon decimal(5,1), Est decimal(12,2), RegEst decimal(12,2), Desv decimal(12,2), Consumo decimal(9,1), Excedidas int, EnRiesgo int);
INSERT @res EXEC api.Estimacion_VsReal @Proyecto = 'SCR', @Nivel = 'tarea', @Detalle = 0;
SET @ok = CASE WHEN (SELECT Issues FROM @res) = 2 AND (SELECT Con FROM @res) = 1 AND (SELECT Sin FROM @res) = 1 AND (SELECT PctCon FROM @res) = 50
                AND (SELECT Est FROM @res) = 10 AND (SELECT RegEst FROM @res) = 3 AND (SELECT Desv FROM @res) = -7 AND (SELECT Consumo FROM @res) = 30
                AND (SELECT Excedidas FROM @res) = 0 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Estimado vs. real (tareas): 2 tareas, 1 sin estimar (50 % capturado); la estimada lleva 3 de 10 h (30 %)';
DELETE @res; INSERT @res EXEC api.Estimacion_VsReal @Proyecto = 'SCR', @Nivel = 'epica', @Detalle = 0;
SET @ok = CASE WHEN (SELECT Issues FROM @res) = 1 AND (SELECT Excedidas FROM @res) = 1 AND (SELECT Desv FROM @res) = 7 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Estimado vs. real (épicas): la épica se excedió 7 h (las automáticas no cuentan como esfuerzo)';
DELETE @res; INSERT @res EXEC api.Estimacion_VsReal @Proyecto = 'SCR', @Detalle = 0;
SET @ok = CASE WHEN (SELECT Issues FROM @res) = 2 AND (SELECT Sin FROM @res) = 1 AND (SELECT Est FROM @res) = 10 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Estimado vs. real sin nivel: compara tareas (épicas y tareas juntas contaban todo dos veces)';
DECLARE @cs TABLE (Clave nvarchar(50), TotalFilas int);
INSERT @cs EXEC api.Issues_Consultar @Columnas = N'clave', @Criterios = N'[{"campo":"jerarquia","operador":"en","valores":["Estándar"]},{"campo":"horas_estimadas_arbol","operador":"vacio"}]';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @cs WHERE Clave LIKE 'SCR-%') = 1 AND EXISTS (SELECT 1 FROM @cs WHERE Clave = 'SCR-7') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Búsqueda: tareas sin estimación';
DELETE @cs; INSERT @cs EXEC api.Issues_Consultar @Columnas = N'clave', @Criterios = N'[{"campo":"consumo_estimacion","operador":"mayor","valor":"100"}]';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @cs) = 1 AND EXISTS (SELECT 1 FROM @cs WHERE Clave = 'SCR-1') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Búsqueda: más del 100 % de la estimación consumido';

DECLARE @h TABLE (Persona nvarchar(200), Proyecto varchar(50), Tipo varchar(30), Issues int, Reg decimal(12,2), Aut decimal(12,2), Total decimal(12,2));
INSERT @h EXEC api.Horas_PorPersona @Desde = '2026-10-01', @Hasta = '2026-11-30', @Epica = 'SCR-1';
SET @ok = CASE WHEN (SELECT Reg FROM @h WHERE Persona = N'Dev Uno') = 8 AND (SELECT Aut FROM @h WHERE Persona = N'Dev Uno') = 16
                AND (SELECT Reg FROM @h WHERE Persona = N'Dev Dos') = 9 AND (SELECT SUM(Total) FROM @h) = 33 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por persona de una épica: Dev Uno 8 h + 16 automáticas, Dev Dos 9 h (sin el tiempo de la mesa de ayuda)';

-- La épica se mueve de proyecto en Jira: cambia su clave (SCR-1 -> NEW-1), no su id. Sus hijos todavía dicen "SCR-1".
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
UPDATE ops.Issue SET Clave = 'NEW-1' WHERE FuenteId = @f AND IssueId = '4999';
DELETE @e; INSERT @e EXEC api.Epicas_Avance @Proyecto = 'SCR';
DELETE @r; INSERT @r EXEC api.Issues_Consultar @Columnas = N'epica,jerarquia', @OrdenarPor = 'clave', @Descendente = 0;
DECLARE @p TABLE (Clave nvarchar(50), Padre nvarchar(50), TotalFilas int);
INSERT @p EXEC api.Issues_Consultar @Columnas = N'padre', @Criterios = N'[{"campo":"clave","operador":"igual","valor":"SCR-7"}]';
SET @ok = CASE WHEN (SELECT Epica FROM @e) = 'NEW-1' AND (SELECT Reg FROM @e) = 17 AND (SELECT Issues FROM @e) = 2
                AND (SELECT Epica FROM @r WHERE Clave = N'SCR-8') = N'NEW-1 · Épica: reportes'
                AND (SELECT Padre FROM @p) = N'NEW-1' AND (SELECT PadreClave FROM ops.Issue WHERE FuenteId = @f AND Clave = 'SCR-7') = 'SCR-1' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Épica movida de proyecto: la jerarquía se une por id y sigue completa (horas, tareas, épica de la subtarea, padre con la clave nueva)';
UPDATE ops.Issue SET Clave = 'SCR-1' WHERE FuenteId = @f AND IssueId = '4999';
GO

/* ===== Horas por sprint ===== */
DECLARE @ok bit;
DECLARE @sp TABLE (SprintId bigint, Proyecto varchar(50), Sprint nvarchar(255), Estado varchar(20), Inicio datetimeoffset, Fin datetimeoffset, Comp datetimeoffset, Vencido bit,
                   Issues int, Comprometidos int, Agregados int, YaTerminados int, Terminados int, TermComp int, Pct decimal(5,1), Arrastrados int,
                   SP decimal(9,2), SPT decimal(9,2), Reg decimal(12,2), Aut decimal(12,2), Est decimal(12,2), SinEst int);
INSERT @sp EXEC api.Sprint_Avance @Proyecto = 'SCR';
SET @ok = CASE WHEN (SELECT Reg FROM @sp WHERE Sprint = N'Sprint 4') = 14 AND (SELECT Aut FROM @sp WHERE Sprint = N'Sprint 4') = 8
                AND (SELECT Reg FROM @sp WHERE Sprint = N'Sprint 3') IS NULL THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Sprint 4 (sigue activo después de su fecha de fin): 14 h registradas (8 de la historia + 6 de la subtarea) y 8 automáticas; el Sprint 3, cerrado antes, no repite esas horas';
SET @ok = CASE WHEN (SELECT Issues FROM @sp WHERE Sprint = N'Sprint 4') = 1 AND (SELECT SinEst FROM @sp WHERE Sprint = N'Sprint 4') = 1
                AND (SELECT Est FROM @sp WHERE Sprint = N'Sprint 4') IS NULL THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Las subtareas no cuentan como issues del sprint; el sprint muestra cuántos no tienen estimación';

DECLARE @h TABLE (Proyecto varchar(50), Sprint nvarchar(255), Estado varchar(20), Inicio datetimeoffset, Fin datetimeoffset, Completado datetimeoffset, Persona nvarchar(200),
                  Issues int, Reg decimal(12,2), Aut decimal(12,2), Total decimal(12,2));
INSERT @h EXEC api.Horas_PorSprint @Proyecto = 'SCR', @Sprint = N'Sprint 4';
SET @ok = CASE WHEN (SELECT Reg FROM @h WHERE Persona = N'Dev Uno') = 8 AND (SELECT Aut FROM @h WHERE Persona = N'Dev Uno') = 8
                AND (SELECT Reg FROM @h WHERE Persona = N'Dev Dos') = 6 AND (SELECT SUM(Total) FROM @h) = 22 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por sprint y persona: Dev Uno 8 h + 8 automáticas (responsable de la historia), Dev Dos 6 h en la subtarea';
DELETE @h; INSERT @h EXEC api.Horas_PorSprint @Estado = 'closed';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @h) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Sprint cerrado sin worklogs en sus fechas: sin horas';
GO

/* ===== Función compartida por el detalle y la búsqueda ===== */
DECLARE @ok bit;
DECLARE @t TABLE (Clave varchar(50), Reg decimal(12,2), Aut decimal(12,2));
INSERT @t SELECT i.Clave, h.HorasRegistradas, h.HorasAutomaticas FROM rpt.vIssue i OUTER APPLY rpt.fn_HorasIssue(i.FuenteId, i.IssueId, i.Clave) h WHERE i.Clave = 'SCR-7';
SET @ok = CASE WHEN (SELECT Reg FROM @t) = 14 AND (SELECT Aut FROM @t) = 8 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'rpt.fn_HorasIssue (la usan el detalle y la búsqueda)';
GO

/* ===== Limpieza: se deja la base como la dejó 010 ===== */
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
DELETE ops.Worklog WHERE FuenteId = @f AND WorklogId IN ('7010', '7011', '7012', '7013', '7014');
DELETE ops.Issue WHERE FuenteId = @f AND IssueId IN ('5010', '5011', '4999');
DELETE sync.IssuePendiente WHERE FuenteId = @f AND IssueId IN ('5010', '5011', '4999', 'SCR-1');
DELETE raw.Documento WHERE FuenteId = @f AND ((Entidad = 'worklog' AND IdExterno IN ('7010', '7011', '7012', '7013', '7014')) OR (Entidad = 'issue' AND IdExterno IN ('5010', '5011', '4999')));
GO

DROP PROCEDURE prueba.Claves; DROP PROCEDURE prueba.Correr; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DE TIEMPOS SCRUM PASARON';
GO
