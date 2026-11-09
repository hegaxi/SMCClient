/* Robustez de la sincronización (diagnóstico de arquitectura):
   1) la compuerta solo bloquea antes de la primera carga; después avisa "datos atrasados";
   2) historial y SLA pendientes persistidos en sync.IssuePendiente (no en la memoria del worker);
   3) carga inicial sin límite de fecha y padres / épicas faltantes encolados para traerlos por clave.
   Ejecutar después de 010 (fuente "prueba", MDA-1 de mesa de ayuda y SCR-7 de Scrum con padre SCR-1). Deja la base como estaba. */
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

/* ===== 1. Compuerta: solo antes de la primera carga ===== */
DECLARE @ok bit;
DECLARE @estado TABLE (Fuente varchar(50), Ultima datetimeoffset, Min int, Vigentes bit, Sinc bit, Pend int, Cuar int, Avisos int, Atrasados bit, MaxMin int, IssuesPend int);
INSERT @estado EXEC api.Sync_Estado @Detalle = 0;
SET @ok = (SELECT CASE WHEN Vigentes = 1 AND Atrasados = 0 THEN 1 ELSE 0 END FROM @estado WHERE Fuente = 'prueba');
EXEC prueba.Afirmar @ok, N'Recién sincronizada: vigente y al día';

-- Jira o el worker llevan dos días sin sincronizar.
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
UPDATE sync.Ejecucion SET Inicio = DATEADD(DAY, -2, Inicio), Fin = DATEADD(DAY, -2, Fin) WHERE FuenteId = @f;
DELETE @estado; INSERT @estado EXEC api.Sync_Estado @Detalle = 0;
SET @ok = (SELECT CASE WHEN Vigentes = 1 AND Atrasados = 1 AND Min >= 2880 AND MaxMin = 30 THEN 1 ELSE 0 END FROM @estado WHERE Fuente = 'prueba');
EXEC prueba.Afirmar @ok, N'Sin sincronizar hace 2 días: sigue vigente (la API no responde 503) y avisa que los datos están atrasados';
UPDATE sync.Ejecucion SET Inicio = DATEADD(DAY, 2, Inicio), Fin = DATEADD(DAY, 2, Fin) WHERE FuenteId = @f;

-- Una entidad que nunca terminó bien (primera carga incompleta) sí bloquea.
DECLARE @x TABLE (FuenteId int);
INSERT @x EXEC sync.Fuente_Registrar @Codigo = 'sin_carga', @UrlBase = N'https://sin-carga.atlassian.net';
DELETE @estado; INSERT @estado EXEC api.Sync_Estado @Detalle = 0;
SET @ok = (SELECT CASE WHEN Vigentes = 0 THEN 1 ELSE 0 END FROM @estado WHERE Fuente = 'sin_carga');
EXEC prueba.Afirmar @ok, N'Fuente sin primera carga: no vigente (la API responde 503 hasta que termine)';
UPDATE cfg.Fuente SET Activa = 0 WHERE Codigo = 'sin_carga';
GO

/* ===== 2. Historial y SLA pendientes en la base ===== */
DECLARE @ok bit, @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'changelog' AND IssueId = '5001')
                AND EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'changelog' AND IssueId = '5002')
                AND EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'sla' AND IssueId = '5001')
                AND NOT EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'sla' AND IssueId = '5002') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Al integrar issues nuevos se encolan su historial y, solo en mesa de ayuda, su SLA';

DECLARE @t TABLE (IssueId varchar(50), Clave varchar(50), TipoProyecto varchar(30));
DECLARE @tomado datetimeoffset(3);
INSERT @t EXEC sync.IssuePendiente_Tomar @Fuente = 'prueba', @Entidad = 'changelog', @TomadoEn = @tomado OUTPUT;
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @t) = 2 AND (SELECT Clave FROM @t WHERE IssueId = '5002') = 'SCR-7'
                AND NOT EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'changelog' AND Intentos <> 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El worker toma los pendientes y queda registrado el intento';

-- Si el worker se cae antes de guardar el historial, los pendientes siguen ahí.
DELETE @t; INSERT @t EXEC sync.IssuePendiente_Tomar @Fuente = 'prueba', @Entidad = 'changelog';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @t) = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Si no se completaron (falla o caída del worker), se vuelven a entregar en la siguiente corrida';

-- Mientras tanto SCR-7 cambia en Jira: se vuelve a encolar después de tomarlo.
WAITFOR DELAY '00:00:00.020';
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Actualizado, Json)
SELECT IdExterno, '2026-11-04T09:00:00-06:00', REPLACE(Json, N'"updated":"2026-11-02T12:00:00.000-0600"', N'"updated":"2026-11-04T09:00:00.000-0600"')
FROM raw.Documento WHERE FuenteId = @f AND Entidad = 'issue' AND IdExterno = '5002';
EXEC prueba.Correr 'issue', 'incremental', @d;
DECLARE @ids sync.IdTipo; INSERT @ids VALUES ('5001'), ('5002');
DECLARE @c TABLE (n int);
INSERT @c EXEC sync.IssuePendiente_Completar @Fuente = 'prueba', @Entidad = 'changelog', @Ids = @ids, @TomadoEn = @tomado;
SET @ok = CASE WHEN (SELECT n FROM @c) = 1
                AND NOT EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'changelog' AND IssueId = '5001')
                AND (SELECT Intentos FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'changelog' AND IssueId = '5002') = 0 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Completar borra lo guardado, pero no un issue que cambió después de tomarlo (se pedirá otra vez)';

-- Reprocesar desde raw (sin cambios en Jira) no vuelve a pedir historiales.
DELETE sync.IssuePendiente WHERE FuenteId = @f AND Entidad IN ('changelog', 'sla');
DECLARE @r TABLE (n int);
INSERT @r EXEC sync.Reprocesar @Fuente = 'prueba', @Entidad = 'issue';
DELETE @d; EXEC prueba.Correr 'issue', 'reproceso', @d;
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad IN ('changelog', 'sla')) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un reproceso o backfill de issues sin cambios no encola historiales';

-- Algo que falla siempre se deja de intentar en cada ciclo: una vez al día tras 5 intentos.
INSERT sync.IssuePendiente (FuenteId, Entidad, IssueId, Clave, Intentos, UltimoIntento) VALUES (@f, 'changelog', '5001', 'MDA-1', 5, SYSDATETIMEOFFSET());
DELETE @t; INSERT @t EXEC sync.IssuePendiente_Tomar @Fuente = 'prueba', @Entidad = 'changelog';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @t) THEN 1 ELSE 0 END;
UPDATE sync.IssuePendiente SET UltimoIntento = DATEADD(DAY, -2, SYSDATETIMEOFFSET()) WHERE FuenteId = @f AND IssueId = '5001';
DELETE @t; INSERT @t EXEC sync.IssuePendiente_Tomar @Fuente = 'prueba', @Entidad = 'changelog';
SET @ok = CASE WHEN @ok = 1 AND (SELECT COUNT(*) FROM @t) = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Tras 5 intentos fallidos se reintenta una vez al día';
DELETE sync.IssuePendiente WHERE FuenteId = @f;
GO

/* ===== 3. Carga inicial completa y padres faltantes ===== */
DECLARE @ok bit, @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
DECLARE @m TABLE (FuenteId int, Entidad varchar(40), MarcaAgua datetimeoffset, Desde datetimeoffset, EsCargaInicial bit);
INSERT @m EXEC sync.MarcaAgua_Obtener @Fuente = 'prueba', @Entidad = 'sin_marca';
SET @ok = CASE WHEN (SELECT Desde FROM @m) = '2000-01-01T00:00:00+00:00' AND (SELECT EsCargaInicial FROM @m) = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Carga inicial sin límite de fecha (DiasCargaInicial = 0): también llegan épicas y padres viejos';

-- SCR-7 menciona a su épica SCR-1, que no está; MDA-1 menciona a un padre de un proyecto excluido.
UPDATE ops.Issue SET PadreClave = 'TST-9' WHERE FuenteId = @f AND Clave = 'MDA-1';
DECLARE @t TABLE (IssueId varchar(50), Clave varchar(50), TipoProyecto varchar(30));
INSERT @t EXEC sync.Padres_Pendientes @Fuente = 'prueba';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @t) = 1 AND (SELECT IssueId FROM @t) = '4999' AND (SELECT Clave FROM @t) = 'SCR-1' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Padres faltantes: se pide la épica SCR-1 por su id (4999); no el padre de un proyecto excluido';

-- Llega la épica: deja de estar pendiente.
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Actualizado, Json) VALUES ('4999', '2025-01-10T08:00:00-06:00', N'{"id":"4999","key":"SCR-1","fields":{
    "summary":"Épica vieja","project":{"id":"901","key":"SCR"},"issuetype":{"id":"10000","name":"Epic","subtask":false,"hierarchyLevel":1},
    "status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},
    "created":"2025-01-02T08:00:00.000-0600","updated":"2025-01-10T08:00:00.000-0600"}}');
EXEC prueba.Correr 'issue', 'padres', @d;
DELETE @t; INSERT @t EXEC sync.Padres_Pendientes @Fuente = 'prueba';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @t) AND NOT EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'padre')
                AND EXISTS (SELECT 1 FROM ops.Issue WHERE FuenteId = @f AND Clave = 'SCR-1' AND NivelJerarquia = 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Cuando llega el padre (traído por clave) deja de estar pendiente';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'changelog' AND IssueId = '4999') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El padre traído también encola su historial';
SET @ok = CASE WHEN (SELECT Valor FROM sync.MarcaAgua WHERE FuenteId = @f AND Entidad = 'issue') >= '2026-11-02' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Traer padres no mueve la marca de agua de issues (su fecha de actualización es vieja)';

/* Limpieza */
UPDATE ops.Issue SET PadreClave = NULL WHERE FuenteId = @f AND Clave = 'MDA-1';
DELETE ops.Issue WHERE FuenteId = @f AND IssueId = '4999';
DELETE raw.Documento WHERE FuenteId = @f AND Entidad = 'issue' AND IdExterno = '4999';
DELETE sync.IssuePendiente WHERE FuenteId = @f;
GO

DROP PROCEDURE prueba.Correr; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DE PENDIENTES DE SINCRONIZACIÓN PASARON';
GO
