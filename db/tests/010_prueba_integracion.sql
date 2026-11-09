/* Prueba de punta a punta de la sincronización con datos FICTICIOS que imitan la forma real de Jira Cloud.
   Simula al worker llamando a los procedimientos sync.* y verifica:
     1. carga inicial de catálogo, issues, worklogs, SLA y changelog;
     2. aislamiento de un documento malo (cuarentena) sin frenar a los demás;
     3. cambios en Jira: campo eliminado, renombrado, recreado con otro ID y campo nuevo;
     4. protección contra un catálogo incompleto;
     5. candado entre workers y resultados de los procedimientos api.*.
   Ejecutar sobre una base RECIÉN desplegada:  sqlcmd -b -I -x -d SMCClient -i tests/010_prueba_integracion.sql */
SET NOCOUNT ON; SET XACT_ABORT ON;
GO
-- Los procedimientos auxiliares viven en un esquema "prueba" (los temporales # no ven los tipos de la base).
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

/* ===== 0. Fuente ===== */
DECLARE @ok bit;
DECLARE @x TABLE (FuenteId int);
INSERT @x EXEC sync.Fuente_Registrar @Codigo = 'prueba', @UrlBase = N'https://prueba.atlassian.net';
SET @ok = (SELECT CASE WHEN COUNT(*) = 9 THEN 1 ELSE 0 END FROM cfg.EntidadSync e JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId WHERE f.Codigo = 'prueba'); EXEC prueba.Afirmar @ok, N'Fuente registrada con 9 entidades';
DECLARE @estado TABLE (Fuente varchar(50), Ultima datetimeoffset, Min int, Vigentes bit, Sinc bit, Pend int, Cuar int, Avisos int, Atrasados bit, MaxMin int, IssuesPend int);
INSERT @estado EXEC api.Sync_Estado @Detalle = 0;
SET @ok = (SELECT CASE WHEN Vigentes = 0 THEN 1 ELSE 0 END FROM @estado WHERE Fuente = 'prueba'); EXEC prueba.Afirmar @ok, N'Sin sincronizar: DatosVigentes = 0 (el controlador respondería 503)';
GO

/* ===== 1. Catálogos ===== */
DECLARE @ok bit;
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Json) VALUES
 ('summary',            N'{"id":"summary","name":"Summary","custom":false,"schema":{"type":"string","system":"summary"}}'),
 ('status',             N'{"id":"status","name":"Status","custom":false,"schema":{"type":"status","system":"status"}}'),
 ('project',            N'{"id":"project","name":"Project","custom":false,"schema":{"type":"project","system":"project"}}'),
 ('issuetype',          N'{"id":"issuetype","name":"Issue Type","custom":false,"schema":{"type":"issuetype","system":"issuetype"}}'),
 ('priority',           N'{"id":"priority","name":"Priority","custom":false,"schema":{"type":"priority","system":"priority"}}'),
 ('assignee',           N'{"id":"assignee","name":"Assignee","custom":false,"schema":{"type":"user","system":"assignee"}}'),
 ('reporter',           N'{"id":"reporter","name":"Reporter","custom":false,"schema":{"type":"user","system":"reporter"}}'),
 ('created',            N'{"id":"created","name":"Created","custom":false,"schema":{"type":"datetime","system":"created"}}'),
 ('updated',            N'{"id":"updated","name":"Updated","custom":false,"schema":{"type":"datetime","system":"updated"}}'),
 ('resolutiondate',     N'{"id":"resolutiondate","name":"Resolved","custom":false,"schema":{"type":"datetime","system":"resolutiondate"}}'),
 ('duedate',            N'{"id":"duedate","name":"Due date","custom":false,"schema":{"type":"date","system":"duedate"}}'),
 ('timespent',          N'{"id":"timespent","name":"Time Spent","custom":false,"schema":{"type":"number","system":"timespent"}}'),
 ('timeoriginalestimate', N'{"id":"timeoriginalestimate","name":"Original estimate","custom":false,"schema":{"type":"number","system":"timeoriginalestimate"}}'),
 ('labels',             N'{"id":"labels","name":"Labels","custom":false,"schema":{"type":"array","items":"string","system":"labels"}}'),
 ('parent',             N'{"id":"parent","name":"Parent","custom":false,"schema":{"type":"issuelink","system":"parent"}}'),
 ('customfield_10020',  N'{"id":"customfield_10020","name":"Sprint","custom":true,"schema":{"type":"array","items":"json","custom":"com.pyxis.greenhopper.jira:gh-sprint","customId":10020}}'),
 ('customfield_10016',  N'{"id":"customfield_10016","name":"Story point estimate","custom":true,"schema":{"type":"number","custom":"com.pyxis.greenhopper.jira:jsw-story-points","customId":10016}}'),
 ('customfield_10010',  N'{"id":"customfield_10010","name":"Request Type","custom":true,"schema":{"type":"sd-customerrequesttype","custom":"com.atlassian.servicedesk:vp-origin","customId":10010}}'),
 ('customfield_10055',  N'{"id":"customfield_10055","name":"Time to resolution","custom":true,"schema":{"type":"sd-servicelevelagreement","custom":"com.atlassian.servicedesk:sd-sla-field","customId":10055}}'),
 ('customfield_10070',  N'{"id":"customfield_10070","name":"Tipo de Solicitud de Atención","custom":true,"schema":{"type":"option","custom":"com.atlassian.jira.plugin.system.customfieldtypes:select","customId":10070}}'),
 ('customfield_10468',  N'{"id":"customfield_10468","name":"Estación Portal","custom":true,"schema":{"type":"array","items":"option","custom":"com.atlassian.jira.plugin.system.customfieldtypes:multiselect","customId":10468}}');
EXEC prueba.Correr 'campo', 'catalogo', @d;

SET @ok = (SELECT CASE WHEN COUNT(*) = 21 THEN 1 ELSE 0 END FROM meta.CampoJira); EXEC prueba.Afirmar @ok, N'Catálogo: 21 campos';
SET @ok = (SELECT CASE WHEN CampoId = 'customfield_10016' THEN 1 ELSE 0 END FROM cfg.MapeoCampo WHERE Rol = 'story_points'); EXEC prueba.Afirmar @ok, N'Rol story_points -> customfield_10016 (por tipo custom)';
SET @ok = (SELECT CASE WHEN CampoId = 'customfield_10020' THEN 1 ELSE 0 END FROM cfg.MapeoCampo WHERE Rol = 'sprint'); EXEC prueba.Afirmar @ok, N'Rol sprint -> customfield_10020';
SET @ok = (SELECT CASE WHEN CampoId = 'customfield_10010' THEN 1 ELSE 0 END FROM cfg.MapeoCampo WHERE Rol = 'tipo_solicitud'); EXEC prueba.Afirmar @ok, N'Rol tipo_solicitud -> customfield_10010';
SET @ok = (SELECT CASE WHEN GuardarValor = 0 THEN 1 ELSE 0 END FROM meta.CampoJira WHERE CampoId = 'customfield_10055'); EXEC prueba.Afirmar @ok, N'Campo SLA no va al EAV (va a ops.IssueSla)';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM sync.Solicitud WHERE Modo = 'backfill'); EXEC prueba.Afirmar @ok, N'Primera carga no genera backfill';

DELETE @d;
INSERT @d (IdExterno, Json) VALUES
 ('1',     N'{"id":"1","name":"To Do","statusCategory":{"id":2,"key":"new"}}'),
 ('3',     N'{"id":"3","name":"In Progress","statusCategory":{"id":4,"key":"indeterminate"}}'),
 ('10001', N'{"id":"10001","name":"Done","statusCategory":{"id":3,"key":"done"}}');
EXEC prueba.Correr 'estado', 'catalogo', @d;

DELETE @d;
INSERT @d (IdExterno, Json) VALUES
 ('900', N'{"id":"900","key":"MDA","name":"Mesa de ayuda (prueba)","projectTypeKey":"service_desk","style":"classic"}'),
 ('901', N'{"id":"901","key":"SCR","name":"Scrum (prueba)","projectTypeKey":"software","style":"classic"}');
EXEC prueba.Correr 'proyecto', 'catalogo', @d;
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM ops.Proyecto WHERE Eliminado = 0); EXEC prueba.Afirmar @ok, N'2 proyectos';
GO

/* ===== 2. Issues (incluye un documento malo, un proyecto excluido y un campo que aún no está en el catálogo) ===== */
DECLARE @ok bit;
EXEC sync.Proyecto_Excluir @Fuente = 'prueba', @Clave = 'TST', @Motivo = N'Proyecto de pruebas';
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Actualizado, Json) VALUES
 ('5001', '2026-11-01T10:00:00-06:00', N'{"id":"5001","key":"MDA-1","fields":{
    "summary":"No puedo entrar al sistema","project":{"id":"900","key":"MDA"},"issuetype":{"id":"10005","name":"Incidente"},
    "status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},"priority":{"id":"2","name":"High"},
    "assignee":{"accountId":"agente-1","displayName":"Agente Uno","accountType":"atlassian","active":true},
    "reporter":{"accountId":"qm:cliente-1","displayName":"cliente@ejemplo.test","accountType":"customer","active":true},
    "created":"2026-10-30T09:15:00.000-0600","updated":"2026-11-01T10:00:00.000-0600","resolutiondate":null,"duedate":"2026-11-05",
    "timespent":10800,"timeoriginalestimate":14400,"labels":["acceso","urgente"],
    "customfield_10010":{"requestType":{"id":"796","name":"Reportar falla"},"currentStatus":{"status":"In Progress"}},
    "customfield_10055":{"id":"86","name":"Time to resolution","completedCycles":[],"slaDisplayFormat":"NEW_SLA_FORMAT"},
    "customfield_10070":{"self":"x","value":"Incidente","id":"10273"},
    "customfield_10468":[{"value":"ESTACIÓN NORTE","id":"10762"},{"value":"ESTACIÓN SUR","id":"10763"}],
    "customfield_99999":"valor de un campo que el catálogo todavía no conoce"}}'),
 ('5002', '2026-11-02T12:00:00-06:00', N'{"id":"5002","key":"SCR-7","fields":{
    "summary":"Historia: pantalla de reportes","project":{"id":"901","key":"SCR"},"issuetype":{"id":"10001","name":"Historia"},
    "status":{"id":"10001","name":"Done","statusCategory":{"key":"done"}},"priority":{"id":"3","name":"Medium"},
    "assignee":{"accountId":"dev-1","displayName":"Dev Uno","accountType":"atlassian","active":true},
    "created":"2026-10-01T08:00:00.000-0600","updated":"2026-11-02T12:00:00.000-0600","resolutiondate":"2026-11-02T12:00:00.000-0600",
    "timespent":28800,"parent":{"id":"4999","key":"SCR-1"},"customfield_10016":5,
    "customfield_10020":[{"id":990,"name":"Sprint 3","state":"closed","boardId":540,"goal":"","startDate":"2026-10-01T11:00:03.281Z","endDate":"2026-10-15T05:30:00.000Z","completeDate":"2026-10-16T18:03:39.409Z"},
                         {"id":991,"name":"Sprint 4","state":"active","boardId":540,"startDate":"2026-10-16T11:00:00.000Z","endDate":"2026-10-30T05:30:00.000Z"}]}}'),
 ('5003', '2026-11-02T13:00:00-06:00', N'{"id":"5003","fields":{"summary":"documento sin key: debe quedar en cuarentena"}}'),
 ('5004', '2026-11-02T11:00:00-06:00', N'{"id":"5004","key":"TST-1","fields":{"summary":"issue de un proyecto de pruebas","project":{"id":"902","key":"TST"},
    "status":{"id":"1","name":"To Do","statusCategory":{"key":"new"}},"created":"2026-11-02T11:00:00.000-0600","updated":"2026-11-02T11:00:00.000-0600"}}');
EXEC prueba.Correr 'issue', 'incremental', @d;

SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM ops.Issue); EXEC prueba.Afirmar @ok, N'2 issues integrados aunque un documento venía mal';
SET @ok = (SELECT CASE WHEN Procesado = 1 THEN 1 ELSE 0 END FROM raw.Documento WHERE Entidad = 'issue' AND IdExterno = '5004'); EXEC prueba.Afirmar @ok, N'Issue de proyecto excluido: se da por procesado sin integrarse';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM ops.Issue WHERE Clave = 'TST-1'); EXEC prueba.Afirmar @ok, N'Proyecto excluido no llega a ops.Issue';
SET @ok = (SELECT CASE WHEN Intentos >= 1 AND Procesado = 0 AND ErrorProceso LIKE N'%sin "id" o "key"%' THEN 1 ELSE 0 END FROM raw.Documento WHERE IdExterno = '5003'); EXEC prueba.Afirmar @ok, N'Documento malo marcado con su error';
SET @ok = (SELECT CASE WHEN COUNT(*) >= 1 THEN 1 ELSE 0 END FROM sync.Evento WHERE Codigo = 'documento.error'); EXEC prueba.Afirmar @ok, N'Aviso documento.error registrado';
SET @ok = (SELECT CASE WHEN Estado = 'parcial' THEN 1 ELSE 0 END FROM sync.Ejecucion WHERE EjecucionId = (SELECT MAX(EjecucionId) FROM sync.Ejecucion WHERE Entidad = 'issue')); EXEC prueba.Afirmar @ok, N'Ejecución con errores queda "parcial"';

SET @ok = (SELECT CASE WHEN EstadoId = '3' AND CategoriaEstado = 'indeterminate' AND Prioridad = 'High' AND ResponsableId = 'agente-1'
                       AND TipoSolicitud = N'Reportar falla' AND TiempoInvertidoSeg = 10800 AND Vencimiento = '2026-11-05'
                       AND Creado = '2026-10-30T09:15:00-06:00' THEN 1 ELSE 0 END FROM ops.Issue WHERE Clave = 'MDA-1');
EXEC prueba.Afirmar @ok, N'Columnas canónicas de MDA-1 (incluye fecha -0600 y request type)';
SET @ok = (SELECT CASE WHEN StoryPoints = 5 AND PadreClave = 'SCR-1' AND CategoriaEstado = 'done' THEN 1 ELSE 0 END FROM ops.Issue WHERE Clave = 'SCR-7'); EXEC prueba.Afirmar @ok, N'Story points y padre de SCR-7';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM ops.IssueCampoValor v JOIN ops.Issue i ON i.IssueSk = v.IssueSk WHERE i.Clave = 'MDA-1' AND v.CampoId = 'customfield_10468'); EXEC prueba.Afirmar @ok, N'Multiselect: una fila por opción';
SET @ok = (SELECT CASE WHEN ValorId = '10273' AND ValorTexto = N'Incidente' THEN 1 ELSE 0 END FROM ops.IssueCampoValor v JOIN ops.Issue i ON i.IssueSk = v.IssueSk WHERE i.Clave = 'MDA-1' AND v.CampoId = 'customfield_10070'); EXEC prueba.Afirmar @ok, N'Select: id y texto de la opción';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM ops.IssueCampoValor v JOIN ops.Issue i ON i.IssueSk = v.IssueSk WHERE i.Clave = 'MDA-1' AND v.CampoId = 'customfield_99999'); EXEC prueba.Afirmar @ok, N'Campo aún no catalogado: su valor no se pierde';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM ops.IssueCampoValor v JOIN ops.Issue i ON i.IssueSk = v.IssueSk WHERE i.Clave = 'MDA-1' AND v.CampoId = 'labels'); EXEC prueba.Afirmar @ok, N'Etiquetas en el EAV';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM ops.IssueCampoValor WHERE CampoId = 'customfield_10055'); EXEC prueba.Afirmar @ok, N'El campo SLA no se duplica en el EAV';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM ops.IssueSprint); EXEC prueba.Afirmar @ok, N'SCR-7 en 2 sprints';
SET @ok = (SELECT CASE WHEN Estado = 'closed' AND Completado IS NOT NULL THEN 1 ELSE 0 END FROM ops.Sprint WHERE SprintId = 990); EXEC prueba.Afirmar @ok, N'Sprint descubierto desde el issue';
SET @ok = (SELECT CASE WHEN TipoCuenta = 'customer' THEN 1 ELSE 0 END FROM ops.Usuario WHERE AccountId = 'qm:cliente-1'); EXEC prueba.Afirmar @ok, N'Cliente del portal registrado como usuario tipo customer';
SET @ok = (SELECT CASE WHEN Valor = '2026-11-02T13:00:00-06:00' THEN 1 ELSE 0 END FROM sync.MarcaAgua WHERE Entidad = 'issue'); EXEC prueba.Afirmar @ok, N'Marca de agua avanzada al máximo Actualizado';
GO

/* ===== 3. Worklogs, eliminados, SLA y changelog ===== */
DECLARE @ok bit;
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Actualizado, Json) VALUES
 ('7001', '2026-11-01T09:00:00-06:00', N'{"id":"7001","issueId":"5001","author":{"accountId":"agente-1","displayName":"Agente Uno","accountType":"atlassian"},"started":"2026-10-30T10:00:00.000-0600","timeSpentSeconds":7200,"created":"2026-10-30T12:00:00.000-0600","updated":"2026-10-30T12:00:00.000-0600"}'),
 ('7002', '2026-11-01T09:30:00-06:00', N'{"id":"7002","issueId":"5001","author":{"accountId":"557058:automation","displayName":"Automation for Jira","accountType":"app"},"started":"2026-10-31T10:00:00.000-0600","timeSpentSeconds":3600,"created":"2026-10-31T12:00:00.000-0600","updated":"2026-10-31T12:00:00.000-0600"}'),
 ('7003', '2026-11-02T09:00:00-06:00', N'{"id":"7003","issueId":"5002","author":{"accountId":"dev-1","displayName":"Dev Uno","accountType":"atlassian"},"started":"2026-10-20T10:00:00.000-0600","timeSpentSeconds":28800,"created":"2026-10-20T19:00:00.000-0600","updated":"2026-10-20T19:00:00.000-0600"}'),
 -- Automation for Jira: 1 día por día hábil. MDA-1 se asignó a agente-1 el 2026-10-30 09:21 (ver changelog).
 ('7004', '2026-11-01T10:00:00-06:00', N'{"id":"7004","issueId":"5001","author":{"accountId":"557058:automation","displayName":"Automation for Jira","accountType":"app"},"started":"2026-10-30T08:00:00.000-0600","timeSpentSeconds":28800,"updated":"2026-10-30T08:00:00.000-0600"}'),
 ('7005', '2026-11-01T10:00:00-06:00', N'{"id":"7005","issueId":"5001","author":{"accountId":"557058:automation","displayName":"Automation for Jira","accountType":"app"},"started":"2026-10-31T08:00:00.000-0600","timeSpentSeconds":28800,"updated":"2026-10-31T08:00:00.000-0600"}');
EXEC prueba.Correr 'worklog', 'incremental', @d;
DELETE @d;
INSERT @d (IdExterno, Json) VALUES ('7002', N'{"worklogId":7002,"updatedTime":1793000000000}');
EXEC prueba.Correr 'worklog_eliminado', 'incremental', @d;
SET @ok = (SELECT CASE WHEN SUM(Segundos) = 93600 THEN 1 ELSE 0 END FROM ops.Worklog WHERE Eliminado = 0); EXEC prueba.Afirmar @ok, N'Worklogs vigentes = 26 h (uno eliminado)';

DELETE @d;
INSERT @d (IdExterno, Json) VALUES
 ('5001', N'{"values":[
   {"id":"86","name":"Time to resolution",
    "ongoingCycle":{"startTime":{"epochMillis":1793370900000},"breachTime":{"epochMillis":1793630100000},"breached":false,"paused":false,"withinCalendarHours":true,
                    "goalDuration":{"millis":28800000},"elapsedTime":{"millis":10800000},"remainingTime":{"millis":18000000}},
    "completedCycles":[{"startTime":{"epochMillis":1793000000000},"stopTime":{"epochMillis":1793010000000},"breachTime":{"epochMillis":1793028800000},"breached":false,
                        "goalDuration":{"millis":28800000},"elapsedTime":{"millis":10000000},"remainingTime":{"millis":18800000}}]},
   {"id":"87","name":"Time to first response",
    "completedCycles":[{"startTime":{"epochMillis":1793370900000},"stopTime":{"epochMillis":1793390000000},"breached":true,
                        "goalDuration":{"millis":14400000},"elapsedTime":{"millis":19100000},"remainingTime":{"millis":-4700000}}]}]}'),
 ('5999', N'{"values":[]}');   -- issue que aún no existe: se pospone
EXEC prueba.Correr 'sla', 'incremental', @d;
SET @ok = (SELECT CASE WHEN COUNT(*) = 3 THEN 1 ELSE 0 END FROM ops.IssueSla); EXEC prueba.Afirmar @ok, N'SLA: 3 ciclos (1 en curso + 2 completados)';
SET @ok = (SELECT CASE WHEN Incumplido = 1 THEN 1 ELSE 0 END FROM ops.IssueSla WHERE SlaId = '87'); EXEC prueba.Afirmar @ok, N'SLA de primera respuesta incumplido';
SET @ok = (SELECT CASE WHEN Procesado = 0 AND Intentos = 0 THEN 1 ELSE 0 END FROM raw.Documento WHERE Entidad = 'sla' AND IdExterno = '5999'); EXEC prueba.Afirmar @ok, N'SLA de un issue inexistente queda pendiente (sin error)';

DELETE @d;
INSERT @d (IdExterno, Json) VALUES
 ('5001', N'{"issueId":"5001","histories":[
   {"id":"h1","author":{"accountId":"agente-1"},"created":"2026-10-30T09:20:00.000-0600","items":[{"field":"status","fieldtype":"jira","fieldId":"status","from":"1","fromString":"To Do","to":"3","toString":"In Progress"}]},
   {"id":"h2","author":{"accountId":"agente-1"},"created":"2026-10-30T09:21:00.000-0600","items":[{"field":"assignee","fieldtype":"jira","fieldId":"assignee","from":null,"to":"agente-1"},
                                                                                                {"field":"Tipo de Solicitud de Atención","fieldtype":"custom","fieldId":"customfield_10070","fromString":null,"toString":"Incidente"}]}]}');
EXEC prueba.Correr 'changelog', 'incremental', @d;
SET @ok = (SELECT CASE WHEN COUNT(*) = 3 THEN 1 ELSE 0 END FROM ops.IssueCambio); EXEC prueba.Afirmar @ok, N'Changelog: 3 cambios (incluye un campo personalizado)';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM rpt.vTransicionEstado WHERE Clave = 'MDA-1'); EXEC prueba.Afirmar @ok, N'Transición de estado visible en rpt.vTransicionEstado';
SET @ok = (SELECT CASE WHEN Origen = 'manual' AND AtribuidoAId = 'agente-1' AND MetodoAtribucion = 'autor' THEN 1 ELSE 0 END FROM rpt.vWorklog WHERE WorklogId = '7001'); EXEC prueba.Afirmar @ok, N'Worklog manual: se atribuye a su autor';
SET @ok = (SELECT CASE WHEN Origen = 'automatico' AND AtribuidoAId = 'agente-1' AND MetodoAtribucion = 'historial' THEN 1 ELSE 0 END FROM rpt.vWorklog WHERE WorklogId = '7005'); EXEC prueba.Afirmar @ok, N'Worklog automático: se atribuye al responsable que tenía el issue ese día';
SET @ok = (SELECT CASE WHEN Origen = 'automatico' AND AtribuidoAId IS NULL AND AtribuidoA = N'(Sin responsable)' THEN 1 ELSE 0 END FROM rpt.vWorklog WHERE WorklogId = '7004'); EXEC prueba.Afirmar @ok, N'Worklog automático antes de asignar el issue: sin responsable';
SET @ok = (SELECT CASE WHEN Autor = N'Automation for Jira' THEN 1 ELSE 0 END FROM rpt.vWorklog WHERE WorklogId = '7005'); EXEC prueba.Afirmar @ok, N'El autor original de Jira se conserva';
SET @ok = (SELECT CASE WHEN AtribuidoAId = 'dev-1' AND MetodoAtribucion = 'autor' THEN 1 ELSE 0 END FROM rpt.vWorklog WHERE WorklogId = '7003'); EXEC prueba.Afirmar @ok, N'Worklog manual de otro proyecto: su autor';
GO

/* ===== 4. Cambios en Jira ===== */
-- customfield_10070 eliminado, customfield_10468 renombrado, Story points recreado con otro ID, campo nuevo customfield_20000.
DECLARE @ok bit;
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Json)
SELECT IdExterno, Json FROM raw.Documento
WHERE Entidad = 'campo' AND IdExterno NOT IN ('customfield_10070', 'customfield_10468', 'customfield_10016');
INSERT @d (IdExterno, Json) VALUES
 ('customfield_10468', N'{"id":"customfield_10468","name":"Estación","custom":true,"schema":{"type":"array","items":"option","custom":"com.atlassian.jira.plugin.system.customfieldtypes:multiselect","customId":10468}}'),
 ('customfield_10099', N'{"id":"customfield_10099","name":"Story Points","custom":true,"schema":{"type":"number","custom":"com.pyxis.greenhopper.jira:jsw-story-points","customId":10099}}'),
 ('customfield_20000', N'{"id":"customfield_20000","name":"Área responsable","custom":true,"schema":{"type":"option","custom":"com.atlassian.jira.plugin.system.customfieldtypes:select","customId":20000}}');
EXEC prueba.Correr 'campo', 'catalogo', @d;

SET @ok = (SELECT CASE WHEN Activo = 0 AND FechaBaja IS NOT NULL THEN 1 ELSE 0 END FROM meta.CampoJira WHERE CampoId = 'customfield_10070'); EXEC prueba.Afirmar @ok, N'Campo eliminado en Jira: inactivo, no borrado';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM ops.IssueCampoValor WHERE CampoId = 'customfield_10070'); EXEC prueba.Afirmar @ok, N'Valores históricos del campo eliminado se conservan';
SET @ok = (SELECT CASE WHEN Nombre = N'Estación' THEN 1 ELSE 0 END FROM meta.CampoJira WHERE CampoId = 'customfield_10468'); EXEC prueba.Afirmar @ok, N'Campo renombrado (mismo ID)';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM meta.CampoJiraCambio WHERE TipoCambio = 'renombre' AND CampoId = 'customfield_10468'); EXEC prueba.Afirmar @ok, N'Renombre en la bitácora';
SET @ok = (SELECT CASE WHEN CampoId = 'customfield_10099' THEN 1 ELSE 0 END FROM cfg.MapeoCampo WHERE Rol = 'story_points'); EXEC prueba.Afirmar @ok, N'Story points recreado: el rol se reasignó solo al nuevo ID';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM sync.Evento WHERE Codigo = 'rol.cambio'); EXEC prueba.Afirmar @ok, N'Aviso rol.cambio';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM sync.Evento WHERE Codigo = 'campo.baja'); EXEC prueba.Afirmar @ok, N'Aviso campo.baja';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM sync.Evento WHERE Codigo = 'campo.alta'); EXEC prueba.Afirmar @ok, N'Aviso campo.alta';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM sync.Solicitud WHERE Modo = 'backfill' AND Estado = 'pendiente'); EXEC prueba.Afirmar @ok, N'Backfill programado para los 2 campos nuevos';
SET @ok = (SELECT CASE WHEN COUNT(*) = 3 THEN 1 ELSE 0 END FROM raw.Documento WHERE Entidad = 'issue' AND Procesado = 0 AND Intentos = 0); EXEC prueba.Afirmar @ok, N'Issues marcados para reprocesar desde raw (incluye el del proyecto excluido)';

-- El worker atiende el backfill de customfield_10099 (JQL cf[10099] is not EMPTY).
DECLARE @s TABLE (SolicitudId bigint, Fuente varchar(50), Entidad varchar(40), Modo varchar(20), Parametros nvarchar(max));
INSERT @s EXEC sync.Solicitud_Tomar @Propietario = N'worker-1';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 AND MAX(Modo) = 'backfill' THEN 1 ELSE 0 END FROM @s); EXEC prueba.Afirmar @ok, N'El worker toma la solicitud de backfill';
DECLARE @marca datetimeoffset(3) = (SELECT Valor FROM sync.MarcaAgua WHERE Entidad = 'issue');
DELETE @d;
INSERT @d (IdExterno, Actualizado, Json)
SELECT '5002', '2026-11-02T12:00:00-06:00', JSON_MODIFY(Json, '$.fields.customfield_10099', 8) FROM raw.Documento WHERE Entidad = 'issue' AND IdExterno = '5002';
EXEC prueba.Correr 'issue', 'backfill', @d;
DECLARE @sid bigint = (SELECT SolicitudId FROM @s);
EXEC sync.Solicitud_Terminar @SolicitudId = @sid;
-- El reproceso pendiente de MDA-1 también corre (sigue en raw).
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
EXEC sync.Procesar_Pendientes @FuenteId = @f, @Entidad = 'issue';

SET @ok = (SELECT CASE WHEN StoryPoints = 8 THEN 1 ELSE 0 END FROM ops.Issue WHERE Clave = 'SCR-7'); EXEC prueba.Afirmar @ok, N'Después del backfill, SCR-7 tiene los story points del campo nuevo';
SET @ok = (SELECT CASE WHEN Valor = @marca THEN 1 ELSE 0 END FROM sync.MarcaAgua WHERE Entidad = 'issue'); EXEC prueba.Afirmar @ok, N'El backfill no mueve la marca de agua';
GO

/* ===== 5. Catálogo incompleto: no se da de baja nada ===== */
DECLARE @ok bit;
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Json) SELECT TOP (3) IdExterno, Json FROM raw.Documento WHERE Entidad = 'campo' ORDER BY IdExterno;
EXEC prueba.Correr 'campo', 'catalogo', @d;
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM meta.CampoJira WHERE Activo = 0); EXEC prueba.Afirmar @ok, N'Catálogo de 3 campos: no hubo bajas masivas (siguen solo las 2 bajas reales)';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM sync.Evento WHERE Codigo = 'campo.catalogo_incompleto'); EXEC prueba.Afirmar @ok, N'Aviso campo.catalogo_incompleto';
GO

/* ===== 6. Candado y API ===== */
DECLARE @ok bit;
DECLARE @ej bigint, @fallo bit = 0;
EXEC sync.Ejecucion_Iniciar @Fuente = 'prueba', @Entidad = 'issue', @Modo = 'incremental', @Propietario = N'worker-1', @EjecucionId = @ej OUTPUT;
BEGIN TRY
    DECLARE @ej2 bigint;
    EXEC sync.Ejecucion_Iniciar @Fuente = 'prueba', @Entidad = 'issue', @Modo = 'incremental', @Propietario = N'worker-2', @EjecucionId = @ej2 OUTPUT;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50010 SET @fallo = 1;
END CATCH;
EXEC prueba.Afirmar @fallo, N'Un segundo worker no puede sincronizar la misma fuente (error 50010)';
EXEC sync.Ejecucion_Finalizar @EjecucionId = @ej, @Estado = 'ok';
EXEC sync.Candado_Liberar @Fuente = 'prueba', @Propietario = N'worker-1';

-- Un worker que muere deja su ejecución "corriendo"; la siguiente que tome el candado la cierra.
DECLARE @muerta bigint, @nueva bigint;
EXEC sync.Ejecucion_Iniciar @Fuente = 'prueba', @Entidad = 'worklog', @Modo = 'incremental', @Propietario = N'worker-muerto', @EjecucionId = @muerta OUTPUT;
UPDATE c SET ExpiraEn = DATEADD(MINUTE, -1, SYSDATETIMEOFFSET()) FROM sync.Candado c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId WHERE f.Codigo = 'prueba';  -- el candado del muerto expira
EXEC sync.Ejecucion_Iniciar @Fuente = 'prueba', @Entidad = 'worklog', @Modo = 'incremental', @Propietario = N'worker-1', @EjecucionId = @nueva OUTPUT;
SET @ok = (SELECT CASE WHEN Estado = 'error' AND Mensaje LIKE N'Abandonada%' THEN 1 ELSE 0 END FROM sync.Ejecucion WHERE EjecucionId = @muerta); EXEC prueba.Afirmar @ok, N'Ejecución abandonada por un worker caído se cierra al tomar el candado';
EXEC sync.Ejecucion_Finalizar @EjecucionId = @nueva, @Estado = 'ok';
EXEC sync.Candado_Liberar @Fuente = 'prueba', @Propietario = N'worker-1';

DECLARE @estado TABLE (Fuente varchar(50), Ultima datetimeoffset, Min int, Vigentes bit, Sinc bit, Pend int, Cuar int, Avisos int, Atrasados bit, MaxMin int, IssuesPend int);
INSERT @estado EXEC api.Sync_Estado @Detalle = 0;
SET @ok = (SELECT CASE WHEN Vigentes = 1 THEN 1 ELSE 0 END FROM @estado WHERE Fuente = 'prueba'); EXEC prueba.Afirmar @ok, N'Después de sincronizar: DatosVigentes = 1';

DECLARE @h TABLE (Persona nvarchar(255), Proyecto varchar(50), TipoProyecto varchar(30), Issues int, Registradas decimal(12,2), Automaticas decimal(12,2), Totales decimal(12,2));
INSERT @h EXEC api.Horas_PorPersona @Desde = '2026-10-01', @Hasta = '2026-11-30';
SET @ok = (SELECT CASE WHEN SUM(Registradas) = 10 AND SUM(Automaticas) = 16 AND SUM(Totales) = 26 THEN 1 ELSE 0 END FROM @h); EXEC prueba.Afirmar @ok, N'api.Horas_PorPersona: 10 h registradas + 16 h automáticas';
SET @ok = (SELECT CASE WHEN Registradas = 2 AND Automaticas = 8 THEN 1 ELSE 0 END FROM @h WHERE Persona = N'Agente Uno'); EXEC prueba.Afirmar @ok, N'Agente Uno: 2 h registradas y 8 h automáticas de cuando era responsable';
SET @ok = (SELECT CASE WHEN Automaticas = 8 AND Registradas = 0 THEN 1 ELSE 0 END FROM @h WHERE Persona = N'(Sin responsable)'); EXEC prueba.Afirmar @ok, N'Horas automáticas sin responsable quedan visibles aparte';
DELETE @h;
INSERT @h EXEC api.Horas_PorPersona @Desde = '2026-10-01', @Hasta = '2026-11-30', @Origen = 'manual';
SET @ok = (SELECT CASE WHEN SUM(Totales) = 10 THEN 1 ELSE 0 END FROM @h); EXEC prueba.Afirmar @ok, N'Filtro @Origen = manual';

DECLARE @sla TABLE (Proyecto varchar(50), Sla nvarchar(255), Ciclos int, Cumplidos int, Incumplidos int, EnCurso int, Pct decimal(5,1), HorasProm decimal(10,2), EnCursoCerrado int);
INSERT @sla EXEC api.Sla_Resumen @Desde = '2026-10-01', @Hasta = '2026-11-30', @TicketsSinSla = 0;
SET @ok = (SELECT CASE WHEN SUM(Incumplidos) >= 1 AND SUM(Ciclos) = 3 THEN 1 ELSE 0 END FROM @sla); EXEC prueba.Afirmar @ok, N'api.Sla_Resumen';

DECLARE @b TABLE (Clave varchar(50), Proyecto varchar(50), TipoProyecto varchar(30), TipoIssue nvarchar(255), TipoSolicitud nvarchar(255), Resumen nvarchar(1000),
                  Estado nvarchar(255), Categoria varchar(20), Prioridad nvarchar(100), Responsable nvarchar(255), Informante nvarchar(255), SP decimal(9,2),
                  Horas decimal(12,2), Est decimal(12,2), Creado datetimeoffset, Act datetimeoffset, Res datetimeoffset, Venc date, Total int);
INSERT @b EXEC api.Issues_Buscar @TipoProyecto = 'service_desk';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 AND MAX(Clave) = 'MDA-1' AND MAX(Estado) = N'In Progress' THEN 1 ELSE 0 END FROM @b); EXEC prueba.Afirmar @ok, N'api.Issues_Buscar filtra mesa de ayuda';

DECLARE @sp TABLE (SprintId bigint, Proyecto varchar(50), Sprint nvarchar(255), Estado varchar(20), Inicio datetimeoffset, Fin datetimeoffset, Comp datetimeoffset, Vencido bit,
                   Issues int, Comprometidos int, Agregados int, YaTerminados int, Terminados int, TermComp int, Pct decimal(5,1), Arrastrados int,
                   SP decimal(9,2), SPT decimal(9,2), HorasReg decimal(12,2), HorasAut decimal(12,2), HorasEst decimal(12,2), SinEst int);
INSERT @sp EXEC api.Sprint_Avance @Proyecto = 'SCR';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 AND SUM(SPT) = 16 THEN 1 ELSE 0 END FROM @sp); EXEC prueba.Afirmar @ok, N'api.Sprint_Avance (8 SP terminados en cada sprint)';

EXEC api.Issue_Detalle @Clave = 'MDA-1';
PRINT N'';
DROP PROCEDURE prueba.Afirmar; DROP PROCEDURE prueba.Correr; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS PASARON';
GO
