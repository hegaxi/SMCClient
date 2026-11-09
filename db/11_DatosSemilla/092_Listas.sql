/* Parámetros que se eligen de una lista en lugar de escribirse (la interfaz los muestra como lista desplegable o casillas):
   smc:origen       'Procedimiento:ColumnaValor[:ColumnaEtiqueta[:ColumnaDescripcion]]': un procedimiento del esquema api
                    que se ejecuta con los permisos del usuario. Si no lo puede ejecutar, el campo vuelve a ser de texto.
   smc:multiple     separador cuando se pueden elegir varios (se envían unidos con él): ',' o '|'
   smc:origenLibre  1 = además de elegir, se puede escribir un valor nuevo (alta de un usuario o un rol) */
DECLARE @l TABLE (Objeto nvarchar(300), Parametro sysname, Origen nvarchar(400), Multiple nvarchar(10) NULL, Libre bit NOT NULL DEFAULT 0);
INSERT @l (Objeto, Parametro, Origen, Multiple, Libre) VALUES
 -- Usuarios, roles y clientes
 ('api.Usuario_Guardar',                '@Login',          N'Usuarios_Listar:Login:Login:Nombre',          NULL, 1),
 ('api.Usuario_Guardar',                '@Roles',          N'Roles_Listar:Nombre:Nombre:Descripcion',      N',', 0),
 ('api.Rol_Guardar',                    '@Nombre',         N'Roles_Listar:Nombre:Nombre:Descripcion',      NULL, 1),
 ('api.Rol_Eliminar',                   '@Nombre',         N'Roles_Listar:Nombre:Nombre:Descripcion',      NULL, 0),
 ('api.Usuario_Organizaciones_Guardar', '@Login',          N'Usuarios_Externos_Listar:Login:Login:Nombre', NULL, 0),
 ('api.Usuario_Organizaciones_Guardar', '@Organizaciones', N'Organizaciones_Listar:Organizacion',          N'|', 0),
 ('api.Auditoria_Listar',               '@Usuario',        N'Usuarios_Listar:Login:Login:Nombre',          NULL, 0),
 -- Proyecto en las consultas
 ('api.Horas_Arbol',                    '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Issues_Buscar',                  '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Horas_PorPersona',               '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Horas_PorPersonaArbol',          '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Horas_PorSprint',                '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Horas_PorSprintArbol',           '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Estimacion_VsReal',              '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Sprint_Avance',                  '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Epicas_Avance',                  '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Sla_Resumen',                    '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 ('api.Sla_EnRiesgo',                   '@Proyecto',       N'Proyectos_Listar:Clave:Clave:Nombre',         NULL, 0),
 -- Sincronización y monitoreo
 ('api.Sync_Solicitar',                 '@Fuente',         N'Sync_Estado:Fuente',                          NULL, 0),
 ('api.Sync_Frecuencia_Guardar',        '@Fuente',         N'Sync_Estado:Fuente',                          NULL, 0),
 ('api.Sync_Frecuencia_Guardar',        '@Entidad',        N'Sync_Frecuencias_Listar:Entidad',             NULL, 0),
 ('api.Sync_Antiguedad_Guardar',        '@Fuente',         N'Sync_Estado:Fuente',                          NULL, 0),
 ('api.Mapeos_Listar',                  '@Fuente',         N'Sync_Estado:Fuente',                          NULL, 0),
 ('api.Campos_Listar',                  '@Fuente',         N'Sync_Estado:Fuente',                          NULL, 0),
 ('api.Mapeo_Establecer',               '@Fuente',         N'Sync_Estado:Fuente',                          NULL, 0),
 ('api.Mapeo_Establecer',               '@Rol',            N'Mapeos_Listar:Rol:Rol:Descripcion',           NULL, 0),
 ('api.Mapeo_Establecer',               '@CampoId',        N'Campos_Listar:CampoId:Nombre:CampoId',        NULL, 0),
 ('api.Aviso_Atender',                  '@EventoId',       N'Avisos_Listar:EventoId:Mensaje:Fecha',        NULL, 0);

DECLARE @o nvarchar(300), @p sysname, @origen nvarchar(400), @mult nvarchar(10), @libre bit;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT Objeto, Parametro, Origen, Multiple, Libre FROM @l
    WHERE EXISTS (SELECT 1 FROM sys.parameters x WHERE x.object_id = OBJECT_ID(Objeto) AND x.name = Parametro);
OPEN c; FETCH c INTO @o, @p, @origen, @mult, @libre;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Parametro = @p, @Nombre = N'smc:origen', @Valor = @origen;
    IF @mult IS NOT NULL EXEC adm.Descripcion_Establecer @Objeto = @o, @Parametro = @p, @Nombre = N'smc:multiple', @Valor = @mult;
    IF @libre = 1 EXEC adm.Descripcion_Establecer @Objeto = @o, @Parametro = @p, @Nombre = N'smc:origenLibre', @Valor = N'1';
    FETCH c INTO @o, @p, @origen, @mult, @libre;
END;
CLOSE c; DEALLOCATE c;

-- Textos de ayuda acordes a la lista (ya no se escriben a mano).
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Login', N'MS_Description', N'Elija un usuario para editarlo o escriba uno nuevo (sin espacios, p. ej. mbravo)';
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Roles', N'MS_Description', N'Marque uno o varios. Al editar, sin marcar ninguno se conservan los actuales';
EXEC adm.Descripcion_Establecer 'api.Rol_Guardar', '@Nombre', N'MS_Description', N'Elija un rol para editarlo o escriba uno nuevo';
EXEC adm.Descripcion_Establecer 'api.Usuario_Organizaciones_Guardar', '@Organizaciones', N'MS_Description', N'Marque las organizaciones cuyos tickets verá el cliente';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Proyecto', N'MS_Description', N'Vacío = todos los proyectos';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', NULL, N'smc:resultados', N'Proyectos, épicas, tareas y subtareas';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Desde', N'MS_Description', N'Fecha del registro de tiempo. Vacío = desde el inicio';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Hasta', N'MS_Description', N'Vacío = hasta hoy';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Persona', N'MS_Description', N'Parte del nombre de quien registró (o a quien se atribuyen las automáticas)';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@SoloConHoras', N'MS_Description', N'Sí = oculta lo que no tiene horas en el periodo';
GO
