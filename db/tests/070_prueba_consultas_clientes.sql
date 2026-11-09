/* Comentarios, consultas personalizadas, clientes externos limitados a su organización y configuración de la
   sincronización. Ejecutar después de 010. Los datos que agrega se borran al final. */
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
/* Claves que devuelve una consulta personalizada para un usuario. */
CREATE OR ALTER PROCEDURE prueba.Ver @ConsultaId int, @Login nvarchar(100), @Claves nvarchar(400) OUTPUT
AS
BEGIN
    DECLARE @r TABLE (n int IDENTITY, Clave nvarchar(50), Resumen nvarchar(1000), Organizacion nvarchar(400), TotalFilas int);
    INSERT @r (Clave, Resumen, Organizacion, TotalFilas) EXEC api.ConsultaPersonalizada_Ejecutar @ConsultaId = @ConsultaId, @OrdenarPor = 'clave', @Descendente = 0, @UsuarioActual = @Login;
    SELECT @Claves = ISNULL(STRING_AGG(Clave, N',') WITHIN GROUP (ORDER BY n), N'') FROM @r;
END;
GO

/* ===== Datos: campo Organizations de JSM y dos tickets de clientes distintos ===== */
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba'), @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();
IF NOT EXISTS (SELECT 1 FROM meta.CampoJira WHERE FuenteId = @f AND CampoId = 'customfield_10002')
    INSERT meta.CampoJira (FuenteId, CampoId, Nombre, EsCustom, TipoSchema, ItemsSchema, TipoCustom, GuardarValor, PrimeraVez, UltimaVez)
    VALUES (@f, 'customfield_10002', N'Organizations', 1, 'array', 'sd-customerorganization', N'com.atlassian.servicedesk:sd-customer-organizations', 1, @ahora, @ahora);
DELETE cfg.MapeoCampo WHERE FuenteId = @f AND Rol = 'organizacion';
INSERT cfg.MapeoCampo (FuenteId, Rol, CampoId, Origen) VALUES (@f, 'organizacion', 'customfield_10002', 'auto');

DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Actualizado, Json) VALUES
 ('6001', '2026-11-05T10:00:00-06:00', N'{"id":"6001","key":"MDA-50","fields":{"summary":"Falla en la báscula","project":{"id":"900","key":"MDA"},
   "issuetype":{"id":"10005","name":"Incidente"},"status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},
   "created":"2026-11-04T09:00:00.000-0600","updated":"2026-11-05T10:00:00.000-0600","customfield_10002":[{"id":"202","name":"ACME"}]}}'),
 ('6002', '2026-11-05T11:00:00-06:00', N'{"id":"6002","key":"MDA-51","fields":{"summary":"Alta de usuario","project":{"id":"900","key":"MDA"},
   "issuetype":{"id":"10005","name":"Incidente"},"status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},
   "created":"2026-11-04T10:00:00.000-0600","updated":"2026-11-05T11:00:00.000-0600","customfield_10002":[{"id":"203","name":"Globex"}]}}');
EXEC prueba.Correr 'issue', 'incremental', @d;
GO

/* ===== Comentarios ===== */
DECLARE @ok bit, @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM sync.IssuePendiente WHERE FuenteId = @f AND Entidad = 'comentario' AND IssueId = '6001') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un issue nuevo encola sus comentarios';
DECLARE @d sync.DocumentoTipo;
INSERT @d (IdExterno, Json) VALUES ('6001', N'{"issueId":"6001","comments":[
   {"id":"9001","author":{"accountId":"agente-1","displayName":"Agente Uno","accountType":"atlassian"},"body":"Se programó el reinicio de la báscula.","jsdPublic":true,"created":"2026-11-04T11:00:00.000-0600","updated":"2026-11-04T11:00:00.000-0600"},
   {"id":"9002","author":{"accountId":"agente-2","displayName":"Agente Dos","accountType":"atlassian"},"body":"Nota interna: revisar el firmware.","jsdPublic":false,"created":"2026-11-04T12:00:00.000-0600","updated":"2026-11-04T12:00:00.000-0600"}]}');
EXEC prueba.Correr 'comentario', 'incremental', @d;
SET @ok = CASE WHEN (SELECT COUNT(*) FROM ops.Comentario WHERE FuenteId = @f AND IssueId = '6001' AND Eliminado = 0) = 2
                AND (SELECT Publico FROM ops.Comentario WHERE FuenteId = @f AND ComentarioId = '9001') = 1
                AND (SELECT Publico FROM ops.Comentario WHERE FuenteId = @f AND ComentarioId = '9002') = 0
                AND EXISTS (SELECT 1 FROM ops.Usuario WHERE FuenteId = @f AND AccountId = 'agente-2') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Comentarios integrados: uno público para el cliente y una nota interna; el autor queda registrado';

DECLARE @r TABLE (Clave nvarchar(50), Comentarios int, Ultimo datetimeoffset, TotalFilas int);
INSERT @r EXEC api.Issues_Consultar @Columnas = N'comentarios,ultimo_comentario', @Criterios = N'[{"campo":"comentario_texto","operador":"contiene","valor":"reinicio"}]';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @r) = 1 AND (SELECT Comentarios FROM @r WHERE Clave = 'MDA-50') = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Búsqueda por el texto de los comentarios, con su número y fecha del último';

DELETE @d; INSERT @d (IdExterno, Json) VALUES ('6001', N'{"issueId":"6001","comments":[
   {"id":"9001","author":{"accountId":"agente-1","displayName":"Agente Uno","accountType":"atlassian"},"body":"Se programó el reinicio de la báscula (editado).","jsdPublic":true,"created":"2026-11-04T11:00:00.000-0600","updated":"2026-11-05T09:00:00.000-0600"}]}');
EXEC prueba.Correr 'comentario', 'incremental', @d;
SET @ok = CASE WHEN (SELECT Eliminado FROM ops.Comentario WHERE FuenteId = @f AND ComentarioId = '9002') = 1
                AND (SELECT Cuerpo FROM ops.Comentario WHERE FuenteId = @f AND ComentarioId = '9001') LIKE N'%(editado)%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un comentario editado se actualiza y uno borrado en Jira queda eliminado';
GO

/* ===== Usuarios: administrador, clientes (rol externo) e interno sin acceso ===== */
DECLARE @t TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
IF NOT EXISTS (SELECT 1 FROM seg.Usuario u WHERE seg.fn_EsAdministrador(u.UsuarioId) = 1)
    EXEC seg.Instalacion_CrearAdministrador @Login = N'jefe70', @Nombre = N'Jefa', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12;
DECLARE @admin nvarchar(200) = (SELECT TOP (1) u.Login FROM seg.Usuario u WHERE seg.fn_EsAdministrador(u.UsuarioId) = 1 ORDER BY u.UsuarioId);
INSERT @t EXEC api.Usuario_Guardar @Login = N'cli_acme', @Nombre = N'Cliente ACME', @Roles = N'Cliente', @UsuarioActual = @admin;
INSERT @t EXEC api.Usuario_Guardar @Login = N'cli_sinorg', @Nombre = N'Cliente sin organización', @Roles = N'Cliente', @UsuarioActual = @admin;
INSERT @t EXEC api.Usuario_Guardar @Login = N'interno70', @Nombre = N'Interno', @Roles = N'Consulta', @UsuarioActual = @admin;
DECLARE @x TABLE (Login nvarchar(100), Nombre nvarchar(200), Activo bit, Roles nvarchar(400), Orgs nvarchar(2000), Consultas nvarchar(2000));
INSERT @x EXEC api.Usuario_Organizaciones_Guardar @Login = N'cli_acme', @Organizaciones = N'ACME', @UsuarioActual = @admin;
DECLARE @ok bit = CASE WHEN (SELECT Orgs FROM @x WHERE Login = N'cli_acme') = N'ACME'
                        AND (SELECT Orgs FROM @x WHERE Login = N'cli_sinorg') LIKE N'(sin organización%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Clientes con su organización (y uno sin organización)';
DECLARE @o TABLE (Organizacion nvarchar(400), Tickets int);
INSERT @o EXEC api.Organizaciones_Listar;
SET @ok = CASE WHEN (SELECT Tickets FROM @o WHERE Organizacion = N'ACME') = 1 AND (SELECT Tickets FROM @o WHERE Organizacion = N'Globex') = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Organizaciones de mesa de ayuda que aparecen en los tickets';

-- Un cliente solo ejecuta procedimientos "usuario", aunque le den también un rol interno.
DELETE @t; INSERT @t EXEC api.Usuario_Guardar @Login = N'cli_acme', @Nombre = N'Cliente ACME', @Roles = N'Cliente, Consulta', @UsuarioActual = @admin;
DECLARE @uid int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = N'cli_acme');
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@uid) WHERE Procedimiento = 'ConsultaPersonalizada_Ejecutar')
                AND NOT EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@uid) WHERE Procedimiento IN ('Issues_Buscar', 'Issues_Consultar', 'Issue_Detalle', 'Horas_PorPersona')) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un usuario externo no ve reportes internos aunque tenga también el rol Consulta';
DELETE @t; INSERT @t EXEC api.Usuario_Guardar @Login = N'cli_acme', @Nombre = N'Cliente ACME', @Roles = N'Cliente', @UsuarioActual = @admin;
DECLARE @sql nvarchar(max) = N'EXEC api.Rol_Guardar @Nombre = N''Externo admin'', @Permisos = N''admin'', @EsExterno = 1, @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Un rol externo no puede tener el permiso admin';
GO

/* ===== Consultas personalizadas ===== */
DECLARE @ok bit, @k nvarchar(400), @sql nvarchar(max);
DECLARE @admin nvarchar(200) = (SELECT TOP (1) u.Login FROM seg.Usuario u WHERE seg.fn_EsAdministrador(u.UsuarioId) = 1 ORDER BY u.UsuarioId);
DECLARE @id TABLE (Id int);
INSERT @id EXEC api.ConsultaPersonalizada_Guardar @Nombre = N'Tickets de mesa de ayuda', @Descripcion = N'Tickets abiertos con su organización',
     @Criterios = N'[{"campo":"proyecto","operador":"en","valores":["MDA"]}]', @Columnas = N'resumen,organizacion',
     @CompartirCon = N'rol:Cliente', @UsuarioActual = @admin;
DECLARE @c int = (SELECT Id FROM @id);
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM dash.ConsultaAcceso a JOIN seg.Rol r ON a.Tipo = 'R' AND r.RolId = a.Id WHERE a.ConsultaId = @c AND r.Nombre = N'Cliente') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un administrador publica una búsqueda como consulta personalizada y la comparte con el rol Cliente';
SET @sql = N'EXEC api.ConsultaPersonalizada_Guardar @Nombre = N''x'', @Columnas = N''resumen,(SELECT 1)'', @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Columnas fuera de la lista blanca rechazadas';
SET @sql = N'EXEC api.ConsultaPersonalizada_Guardar @Nombre = N''x'', @Criterios = N''[{"campo":"x","operador":"en","valores":["a"]}]'', @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Criterios inválidos rechazados (mismas reglas que la búsqueda)';
SET @sql = N'EXEC api.ConsultaPersonalizada_Guardar @Nombre = N''Tickets de mesa de ayuda'', @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50409, N'Nombre repetido';
EXEC prueba.AfirmarError N'EXEC api.ConsultaPersonalizada_Guardar @Nombre = N''x'', @UsuarioActual = N''interno70'';', 50403, N'Solo un administrador publica consultas';
SET @sql = N'EXEC api.ConsultaPersonalizada_Guardar @Nombre = N''x'', @CompartirCon = N''nadie'', @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Compartir con un usuario inexistente rechazado';

DECLARE @l TABLE (ConsultaId int, Nombre nvarchar(150), Descripcion nvarchar(500), CompartidaCon nvarchar(1000), FechaCambio datetimeoffset, PuedoEditar bit);
INSERT @l EXEC api.ConsultasPersonalizadas_Listar @UsuarioActual = N'cli_acme';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @l) = 1 AND (SELECT CompartidaCon FROM @l) IS NULL AND (SELECT PuedoEditar FROM @l) = 0 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El cliente ve la consulta en su lista (sin con quién está compartida)';
DELETE @l; INSERT @l EXEC api.ConsultasPersonalizadas_Listar @UsuarioActual = N'interno70';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @l) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un usuario con quien no se compartió no la ve';

EXEC prueba.Ver @ConsultaId = @c, @Login = @admin, @Claves = @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-1,MDA-50,MDA-51' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El administrador ve todos los tickets de la consulta';
EXEC prueba.Ver @ConsultaId = @c, @Login = N'cli_acme', @Claves = @k OUTPUT;
SET @ok = CASE WHEN @k = N'MDA-50' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El cliente de ACME solo ve los tickets de ACME';
EXEC prueba.Ver @ConsultaId = @c, @Login = N'cli_sinorg', @Claves = @k OUTPUT;
SET @ok = CASE WHEN @k = N'' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un cliente sin organización asignada no ve tickets';
SET @sql = CONCAT(N'EXEC api.ConsultaPersonalizada_Ejecutar @ConsultaId = ', @c, N', @UsuarioActual = N''interno70'';');
EXEC prueba.AfirmarError @sql, 50403, N'Ejecutar una consulta no compartida: 403';

DELETE @id; SET @sql = CONCAT(N'EXEC api.ConsultaPersonalizada_Eliminar @ConsultaId = ', @c, N', @UsuarioActual = N''cli_acme'';');
EXEC prueba.AfirmarError @sql, 50403, N'Solo un administrador elimina consultas';
INSERT @id EXEC api.ConsultaPersonalizada_Eliminar @ConsultaId = @c, @UsuarioActual = @admin;
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM dash.Consulta WHERE ConsultaId = @c) AND NOT EXISTS (SELECT 1 FROM dash.ConsultaAcceso WHERE ConsultaId = @c)
                AND EXISTS (SELECT 1 FROM seg.Auditoria WHERE Accion = 'consulta.eliminar') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Eliminar la consulta borra sus accesos y queda en la auditoría';
GO

/* ===== Configuración de la sincronización ===== */
DECLARE @ok bit, @sql nvarchar(max);
DECLARE @admin nvarchar(200) = (SELECT TOP (1) u.Login FROM seg.Usuario u WHERE seg.fn_EsAdministrador(u.UsuarioId) = 1 ORDER BY u.UsuarioId);
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
DECLARE @antes int = (SELECT FrecuenciaMin FROM cfg.EntidadSync WHERE FuenteId = @f AND Entidad = 'issue');
DECLARE @s TABLE (Fuente varchar(50), Entidad varchar(40), Modo varchar(20), Frec int, Activa bit, MaxAnt int, UltimaOk datetimeoffset);
INSERT @s EXEC api.Sync_Frecuencia_Guardar @Fuente = 'prueba', @Entidad = 'issue', @FrecuenciaMin = 5, @UsuarioActual = @admin;
SET @ok = CASE WHEN (SELECT FrecuenciaMin FROM cfg.EntidadSync WHERE FuenteId = @f AND Entidad = 'issue') = 5
                AND (SELECT Frec FROM @s WHERE Fuente = 'prueba' AND Entidad = 'issue') = 5
                AND EXISTS (SELECT 1 FROM seg.Auditoria WHERE Accion = 'sync.frecuencia' AND Objeto = N'prueba/issue') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El administrador cambia la frecuencia de un tipo de dato (queda en la auditoría)';
EXEC prueba.AfirmarError N'EXEC api.Sync_Frecuencia_Guardar @Fuente = ''prueba'', @Entidad = ''issue'', @FrecuenciaMin = 0, @UsuarioActual = N''x'';', 50400, N'Frecuencia fuera de rango';
EXEC prueba.AfirmarError N'EXEC api.Sync_Frecuencia_Guardar @Fuente = ''prueba'', @Entidad = ''nada'', @FrecuenciaMin = 10, @UsuarioActual = N''x'';', 50404, N'Tipo de dato inexistente';
DELETE @s; INSERT @s EXEC api.Sync_Antiguedad_Guardar @Fuente = 'prueba', @MaxAntiguedadMin = 45, @UsuarioActual = @admin;
SET @ok = CASE WHEN (SELECT MaxAntiguedadMin FROM cfg.Fuente WHERE FuenteId = @f) = 45 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El administrador cambia el margen de datos atrasados';
EXEC prueba.AfirmarError N'EXEC api.Sync_Antiguedad_Guardar @Fuente = ''prueba'', @MaxAntiguedadMin = 1, @UsuarioActual = N''x'';', 50400, N'Margen fuera de rango';

-- Atraso por tipo de dato: frecuencia + margen. El catálogo (cada 60 min) no está atrasado a los 50 min.
UPDATE e SET Inicio = DATEADD(MINUTE, -50, SYSDATETIMEOFFSET()), Fin = DATEADD(MINUTE, -50, SYSDATETIMEOFFSET())
FROM sync.Ejecucion e WHERE e.FuenteId = @f AND e.Entidad IN ('campo', 'estado', 'proyecto');
DECLARE @estado TABLE (Fuente varchar(50), Ultima datetimeoffset, Min int, Vigentes bit, Sinc bit, Pend int, Cuar int, Avisos int, Atrasados bit, MaxMin int, IssuesPend int);
INSERT @estado EXEC api.Sync_Estado @Detalle = 0;
SET @ok = (SELECT CASE WHEN Atrasados = 0 AND Min >= 50 THEN 1 ELSE 0 END FROM @estado WHERE Fuente = 'prueba');
EXEC prueba.Afirmar @ok, N'Un catálogo que se pide cada hora no se marca atrasado a los 50 minutos (frecuencia + margen)';

UPDATE cfg.EntidadSync SET FrecuenciaMin = @antes WHERE FuenteId = @f AND Entidad = 'issue';
UPDATE cfg.Fuente SET MaxAntiguedadMin = 30 WHERE FuenteId = @f;
UPDATE sync.Ejecucion SET Inicio = SYSDATETIMEOFFSET(), Fin = SYSDATETIMEOFFSET() WHERE FuenteId = @f AND Entidad IN ('campo', 'estado', 'proyecto');
GO

/* ===== Limpieza ===== */
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'prueba');
DELETE ops.Comentario WHERE FuenteId = @f AND IssueId IN ('6001', '6002');
DELETE ops.Issue WHERE FuenteId = @f AND IssueId IN ('6001', '6002');
DELETE raw.Documento WHERE FuenteId = @f AND IdExterno IN ('6001', '6002') AND Entidad IN ('issue', 'comentario');
DELETE sync.IssuePendiente WHERE FuenteId = @f AND IssueId IN ('6001', '6002');
DELETE cfg.MapeoCampo WHERE FuenteId = @f AND Rol = 'organizacion';
DELETE meta.CampoJira WHERE FuenteId = @f AND CampoId = 'customfield_10002';
DELETE seg.UsuarioRol WHERE UsuarioId IN (SELECT UsuarioId FROM seg.Usuario WHERE Login IN (N'cli_acme', N'cli_sinorg', N'interno70'));
DELETE seg.Usuario WHERE Login IN (N'cli_acme', N'cli_sinorg', N'interno70');
GO

DROP PROCEDURE prueba.Ver; DROP PROCEDURE prueba.Correr; DROP PROCEDURE prueba.AfirmarError; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DE CONSULTAS Y CLIENTES PASARON';
GO
