/* Organización del menú, por tarea. La interfaz (web/src/menu.ts) arma el menú con estas propiedades:
   smc:menu   sección, o sección/subgrupo: N'Buscar', N'Administración/Usuarios y clientes'
   smc:orden  posición: ordena opciones, subgrupos y secciones (cada uno toma el menor orden de lo que contiene)
   smc:padre  procedimiento bajo el que aparece como sub-opción (las acciones cuelgan de su listado)
   Un procedimiento sin smc:menu aparece en "Otras consultas" (lectura) o en Administración › Otras herramientas.
   Las opciones que solo se abren desde otra pantalla llevan smc:oculto = 1 (el permiso no cambia). */
DECLARE @m TABLE (Objeto nvarchar(300), Menu nvarchar(200), Orden int, Padre nvarchar(128) NULL);
INSERT @m VALUES
 ('api.Issues_Consultar',              N'Buscar',                              110, NULL),
 ('api.Issues_Buscar',                 N'Buscar',                              120, NULL),
 ('api.Proyectos_Listar',              N'Buscar',                              130, NULL),

 ('api.Sprint_Avance',                 N'Proyectos Scrum',                     210, NULL),
 ('api.Epicas_Avance',                 N'Proyectos Scrum',                     220, NULL),
 ('api.Horas_PorSprint',               N'Proyectos Scrum',                     230, NULL),

 ('api.Horas_Arbol',                   N'Tiempo',                              305, NULL),
 ('api.Horas_PorPersona',              N'Tiempo',                              310, NULL),
 ('api.Estimacion_VsReal',             N'Tiempo',                              320, NULL),

 ('api.Sla_Resumen',                   N'Mesa de ayuda',                       410, NULL),
 ('api.Sla_EnRiesgo',                  N'Mesa de ayuda',                       420, NULL),

 ('api.Usuarios_Listar',               N'Administración/Usuarios y clientes',  910, NULL),
 ('api.Usuario_Guardar',               N'Administración/Usuarios y clientes',  911, N'Usuarios_Listar'),
 ('api.Usuarios_Externos_Listar',      N'Administración/Usuarios y clientes',  920, NULL),
 ('api.Usuario_Organizaciones_Guardar',N'Administración/Usuarios y clientes',  921, N'Usuarios_Externos_Listar'),
 ('api.Organizaciones_Listar',         N'Administración/Usuarios y clientes',  922, N'Usuarios_Externos_Listar'),

 ('api.Permisos_Matriz',               N'Administración/Roles y permisos',     940, NULL),
 ('api.Roles_Listar',                  N'Administración/Roles y permisos',     945, NULL),
 ('api.Rol_Guardar',                   N'Administración/Roles y permisos',     946, N'Roles_Listar'),
 ('api.Rol_Eliminar',                  N'Administración/Roles y permisos',     947, N'Roles_Listar'),

 ('api.ProyectosSync_Listar',          N'Administración/Sincronización',       958, NULL),
 ('api.Sync_Estado',                   N'Administración/Sincronización',       960, NULL),
 ('api.Sync_Frecuencias_Listar',       N'Administración/Sincronización',       965, NULL),
 ('api.Sync_Frecuencia_Guardar',       N'Administración/Sincronización',       966, N'Sync_Frecuencias_Listar'),
 ('api.Sync_Antiguedad_Guardar',       N'Administración/Sincronización',       967, N'Sync_Frecuencias_Listar'),
 ('api.Mapeos_Listar',                 N'Administración/Sincronización',       970, NULL),
 ('api.Mapeo_Establecer',              N'Administración/Sincronización',       971, N'Mapeos_Listar'),
 ('api.Campos_Listar',                 N'Administración/Sincronización',       975, NULL),

 ('api.Avisos_Listar',                 N'Administración/Monitoreo',            980, NULL),
 ('api.Aviso_Atender',                 N'Administración/Monitoreo',            981, N'Avisos_Listar'),
 ('api.Auditoria_Listar',              N'Administración/Monitoreo',            985, NULL);

DECLARE @o nvarchar(300), @menu nvarchar(200), @orden int, @padre nvarchar(128), @txt nvarchar(20);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto, Menu, Orden, Padre FROM @m WHERE OBJECT_ID(Objeto) IS NOT NULL;
OPEN c; FETCH c INTO @o, @menu, @orden, @padre;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @txt = CAST(@orden AS nvarchar(20));
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:menu', @Valor = @menu;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:orden', @Valor = @txt;
    IF @padre IS NOT NULL
        EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:padre', @Valor = @padre;
    ELSE IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(@o) AND minor_id = 0 AND name = N'smc:padre')
    BEGIN
        DECLARE @esq sysname = PARSENAME(@o, 2), @obj sysname = PARSENAME(@o, 1);
        EXEC sys.sp_dropextendedproperty @name = N'smc:padre', @level0type = N'SCHEMA', @level0name = @esq, @level1type = N'PROCEDURE', @level1name = @obj;
    END;
    FETCH c INTO @o, @menu, @orden, @padre;
END;
CLOSE c; DEALLOCATE c;

-- Se abren desde otra pantalla: el detalle, desde la clave de cualquier resultado; "Sincronizar ahora", desde la barra
-- lateral; eliminar una consulta personalizada, desde la propia consulta.
EXEC adm.Descripcion_Establecer 'api.Issue_Detalle', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Sync_Solicitar', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Eliminar', NULL, N'smc:oculto', N'1';
GO
