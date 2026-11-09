/* Metadatos que lee el controlador único para construir la interfaz y autorizar:
   smc:titulo      nombre corto para el menú
   MS_Description  descripción que ve el usuario
   smc:permiso     categoría: lectura | admin | usuario (tableros, filtros, consultas compartidas) | sesion (lo mínimo
                   para usar la aplicación; lo tiene todo usuario activo). Cada opción del menú se concede por rol en
                   seg.RolPermiso (ver seg.fn_ProcedimientosPermitidos y la pantalla "Permisos por opción")
   smc:opcion      opción de menú que agrupa varios procedimientos de una misma pantalla (p. ej. tableros); sin ella,
                   cada procedimiento es su propia opción
   smc:exentoSync  1 = se puede ejecutar aunque los datos no estén sincronizados
   smc:accion      1 = modifica algo (la interfaz nunca lo ejecuta solo al abrirlo; pide confirmar)
   smc:resultados  títulos de cada conjunto de resultados, separados por '|'
   smc:oculto      1 = no aparece en el menú (lo usa una pantalla propia de la interfaz)
   smc:opciones    (en un parámetro) valores permitidos: valor=Etiqueta|valor2=Etiqueta2 */
DECLARE @p TABLE (Objeto nvarchar(300), Titulo nvarchar(100), Descripcion nvarchar(400), Permiso varchar(10), Exento char(1));
INSERT @p VALUES
 ('api.Sync_Resumen',     N'Resumen de la sincronización', N'Cuándo se sincronizó cada fuente y si los datos están al día (pantalla de sincronización y aviso de atraso).', 'sesion', '1'),
 ('api.Permisos_Matriz',  N'Permisos por opción',        N'Qué opción del menú tiene cada rol: marque o desmarque cada casilla.',                         'admin',   '1'),
 ('api.Rol_Opcion_Establecer', N'Conceder o quitar una opción', N'Concede o quita una opción del menú a un rol.',                                         'admin',   '1');
INSERT @p VALUES
 ('api.Issues_Buscar',    N'Búsqueda rápida',           N'Historias Scrum y tickets de mesa de ayuda con filtros por proyecto, estado, responsable y fechas.', 'lectura', '0'),
 ('api.Issue_Detalle',    N'Detalle de un ticket',      N'Datos, campos personalizados, tiempo registrado, SLA e historial de un ticket o historia.',                   'lectura', '0'),
 ('api.Horas_PorPersonaArbol', N'Horas por persona',     N'Horas de cada persona por proyecto, épica, tarea y subtarea, con subtotales y total: registradas por personas y automáticas por separado. No suma las copias que Automation for Jira hace hacia la tarea, la épica y la OC.', 'lectura', '0'),
 ('api.Horas_PorPersona', N'Horas por persona (tabla)',  N'Horas por persona y proyecto en una tabla (para descargar o usar en tableros): registradas por personas y automáticas (Automation for Jira) por separado, sin las copias automáticas.', 'lectura', '0'),
 ('api.Sla_Resumen',      N'Cumplimiento de SLA',        N'Cumplimiento de SLA por proyecto, medido como JSM: ciclos terminados o vencidos en el periodo. Incluye los tickets que quedaron sin SLA.',                      'lectura', '0'),
 ('api.Sla_EnRiesgo',     N'SLA por vencer',             N'Tickets abiertos con un SLA que vence pronto o que venció en los últimos días, con la prioridad ITIL.',                                     'lectura', '0'),
 ('api.Sprint_Avance',    N'Avance de sprints',          N'Issues, story points y horas registradas dentro de cada sprint (incluye subtareas).',          'lectura', '0'),
 ('api.Epicas_Avance',    N'Avance de épicas',           N'Tareas terminadas, story points, estimación y horas de cada épica (con sus tareas y subtareas).', 'lectura', '0'),
 ('api.Estimacion_VsReal', N'Estimado vs. real',          N'Horas estimadas contra las registradas por personas (con subtareas), desviación, % consumido y tareas sin estimar.', 'lectura', '0'),
 ('api.ConsultasPersonalizadas_Listar', N'Consultas personalizadas', N'Consultas personalizadas compartidas con usted o con su rol.',                         'usuario', '0'),
 ('api.ConsultaPersonalizada_Obtener',  N'Consulta personalizada',   N'Definición de una consulta personalizada.',                                              'usuario', '0'),
 ('api.ConsultaPersonalizada_Ejecutar', N'Ejecutar consulta personalizada', N'Resultados de una consulta personalizada (los clientes ven solo los tickets de su organización).', 'usuario', '0'),
 ('api.ConsultaPersonalizada_Guardar',  N'Publicar consulta personalizada', N'Publica una búsqueda avanzada como consulta personalizada y la comparte con usuarios o roles.', 'admin', '1'),
 ('api.ConsultaPersonalizada_Eliminar', N'Eliminar consulta personalizada', N'Elimina una consulta personalizada.',                                              'admin',   '1'),
 ('api.Usuario_Organizaciones_Guardar', N'Organizaciones de un cliente', N'Organizaciones de mesa de ayuda de un usuario externo: solo verá los tickets de esas organizaciones.', 'admin', '1'),
 ('api.Usuarios_Externos_Listar',       N'Clientes (usuarios externos)', N'Usuarios externos, sus organizaciones y las consultas personalizadas que ven.',       'admin',   '0'),
 ('api.Organizaciones_Listar',          N'Organizaciones de mesa de ayuda', N'Organizaciones que aparecen en los tickets, con su número de tickets.',          'admin',   '0'),
 ('api.Sync_Frecuencias_Listar',        N'Configuración de la sincronización', N'Cada cuántos minutos se sincroniza cada tipo de dato y el margen para avisar de datos atrasados.', 'admin', '1'),
 ('api.Sync_Frecuencia_Guardar',        N'Cambiar frecuencia de sincronización', N'Cada cuántos minutos se pide a Jira un tipo de dato de una fuente.',        'admin',   '1'),
 ('api.Sync_Antiguedad_Guardar',        N'Cambiar margen de datos atrasados', N'Minutos de tolerancia, además de la frecuencia, antes de avisar que los datos están atrasados.', 'admin', '1'),
 ('api.Horas_PorSprintArbol', N'Horas por sprint',      N'Tiempo de cada sprint por persona, tarea y subtarea, con subtotales y total: registradas por personas y automáticas (sin copias).', 'lectura', '0'),
 ('api.Horas_PorSprint',  N'Horas por sprint (tabla)',   N'Horas por sprint y persona en una tabla (para descargar o usar en tableros): registradas y automáticas, incluye subtareas.', 'lectura', '0'),
 ('api.Proyectos_Listar', N'Proyectos',                  N'Proyectos Scrum y de mesa de ayuda que se sincronizan.',                                        'lectura', '0'),
 ('api.Sync_Estado',      N'Estado de la sincronización', N'Cuándo se sincronizó cada fuente y cada tipo de dato.',                                        'lectura', '1'),
 ('api.Sync_Solicitar',   N'Sincronizar ahora',          N'Pide una sincronización inmediata con Jira.',                                                   'lectura', '1'),
 ('api.Campos_Listar',    N'Campos de Jira',             N'Catálogo de campos de Jira y el rol que cumplen en los reportes.',                              'lectura', '1'),
 ('api.Avisos_Listar',    N'Avisos',                     N'Cambios detectados en Jira (campos nuevos o eliminados) y errores de sincronización.',          'admin',   '1'),
 ('api.Aviso_Atender',    N'Marcar aviso como atendido', N'Marca un aviso como atendido.',                                                                 'admin',   '1'),
 ('api.Mapeos_Listar',    N'Mapeo de campos',            N'Qué campo de Jira alimenta cada dato de los reportes (estado, story points, sprint...).',       'admin',   '1'),
 ('api.Mapeo_Establecer', N'Asignar campo a un dato',    N'Asigna manualmente el campo de Jira de un dato; vacío lo devuelve a automático.',              'admin',   '1'),
 ('api.Mi_Usuario',       N'Mi usuario',                 N'Su usuario y sus roles.',                                                                       'sesion',  '1'),
 ('api.Usuarios_Listar',  N'Usuarios',                   N'Usuarios de la aplicación y sus roles.',                                                        'admin',   '1'),
 ('api.Usuario_Guardar',  N'Nuevo o editar usuario',     N'Da de alta o modifica un usuario y sus roles. Al editar, deje vacío lo que no quiera cambiar. La contraseña se asigna en Restablecer contraseña.',                         'admin',   '1'),
 ('api.Roles_Listar',     N'Roles',                      N'Roles y sus permisos.',                                                                         'admin',   '1'),
 ('api.Rol_Guardar',      N'Nuevo o editar rol',         N'Crea o modifica un rol. Al editar, deje vacío lo que no quiera cambiar; los permisos se ajustan mejor en Permisos por opción.',                                                        'admin',   '1'),
 ('api.Rol_Eliminar',     N'Eliminar rol',               N'Elimina un rol sin usuarios asignados.',                                                        'admin',   '1'),
 ('api.Auditoria_Listar', N'Auditoría',                  N'Quién hizo qué en la administración y cuándo.',                                                 'admin',   '1'),
 ('api.Filtros_Listar',   N'Mis filtros',                N'Filtros guardados propios y compartidos.',                                                      'usuario', '1'),
 ('api.Filtro_Guardar',   N'Guardar filtro',             N'Guarda una consulta con sus valores para reutilizarla o usarla en un tablero.',                'usuario', '1'),
 ('api.Filtro_Eliminar',  N'Eliminar filtro',            N'Elimina un filtro guardado que no use ningún widget.',                                         'usuario', '1'),
 ('api.Tableros_Listar',  N'Tableros',                   N'Tableros propios y compartidos.',                                                               'usuario', '1'),
 ('api.Tablero_Guardar',  N'Guardar tablero',            N'Crea o modifica un tablero y con quién se comparte.',                                           'usuario', '1'),
 ('api.Tablero_Eliminar', N'Eliminar tablero',           N'Elimina un tablero con sus widgets.',                                                           'usuario', '1'),
 ('api.Tablero_Obtener',  N'Ver tablero',                N'Un tablero con sus widgets listos para mostrarse.',                                             'usuario', '1'),
 ('api.Widget_Guardar',   N'Guardar widget',             N'Agrega o modifica un widget de un tablero.',                                                    'usuario', '1'),
 ('api.Widget_Eliminar',  N'Quitar widget',              N'Quita un widget de un tablero.',                                                                'usuario', '1'),
 ('api.Widget_Mover',     N'Mover widget',               N'Cambia el orden de un widget.',                                                                 'usuario', '1'),
 ('api.Tablero_Inicio',   N'Tablero de inicio',          N'Elige el tablero que se muestra al entrar.',                                                    'usuario', '1'),
 ('api.Issues_Consultar', N'Búsqueda avanzada',          N'Filtros desde cero sobre cualquier campo de Jira (también los personalizados), con columnas y orden a elegir.', 'lectura', '0'),
 ('api.Issues_Campos',    N'Campos de búsqueda',         N'Campos y operadores disponibles en la búsqueda avanzada.',                                      'lectura', '1'),
 ('api.Issues_Resumir',   N'Resumen de una búsqueda',    N'Conteos, sumas o promedios de una búsqueda avanzada agrupados por un campo, sobre todos los issues.', 'lectura', '0'),
 ('api.Sprints_Listar',      N'Sprints',                  N'Sprints para elegir en las consultas, con su proyecto, estado y fechas.',                       'lectura', '0'),
 ('api.Epicas_Listar',       N'Épicas',                   N'Épicas para elegir en las consultas, con su resumen y estado.',                               'lectura', '0'),
 ('api.Personas_Listar',     N'Personas',                 N'Personas de Jira (responsables y quienes registran tiempo) para elegir en las consultas.',    'lectura', '0'),
 ('api.Horas_Arbol',         N'Horas por proyecto', N'Tiempo por proyecto, épica, tarea y subtarea (uno o todos los proyectos), con subtotales y total: horas de cada elemento y de todo lo que tiene debajo, contra lo estimado. Las copias de Automation for Jira van aparte y no se suman.', 'lectura', '0'),
 ('api.Tiempos_Invertidos',  N'Tiempos invertidos', N'Tiempo registrado con una columna por día, semana, mes, trimestre o año y las agrupaciones que elija (persona, proyecto, épica, tarea, ticket, tipo o estado), con subtotales y total. En horas o en días. No suma las copias de Automation for Jira.', 'lectura', '0'),
 ('api.ProyectosSync_Listar',        N'Proyectos a sincronizar', N'Qué proyectos de Jira se sincronizan: los desactivados no se piden a Jira y se ocultan de los reportes.', 'admin', '1'),
 ('api.ProyectoSync_Establecer',      N'Activar o desactivar un proyecto', N'Activa o desactiva la sincronización de un proyecto.', 'admin', '1'),
 ('api.ProyectosSync_Nuevos_Guardar', N'Sincronizar proyectos nuevos', N'Si un proyecto nuevo en Jira se sincroniza solo o queda desactivado.', 'admin', '1'),
 ('api.Destinatarios_Listar', N'Con quién compartir',   N'Usuarios y roles con quienes se puede compartir un tablero o una consulta.',                  'usuario', '1'),
 ('api.Issues_Valores',   N'Valores de un campo',        N'Valores existentes de un campo, para elegirlos en la búsqueda avanzada.',                       'lectura', '0');

DECLARE @o nvarchar(300), @t nvarchar(100), @d nvarchar(400), @pe varchar(10), @e char(1);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto, Titulo, Descripcion, Permiso, Exento FROM @p;
OPEN c; FETCH c INTO @o, @t, @d, @pe, @e;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Valor = @d;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:titulo', @Valor = @t;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:permiso', @Valor = @pe;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:exentoSync', @Valor = @e;
    FETCH c INTO @o, @t, @d, @pe, @e;
END;
CLOSE c; DEALLOCATE c;

-- Títulos de cada conjunto de resultados (la interfaz los usa como encabezados).
EXEC adm.Descripcion_Establecer 'api.Sync_Solicitar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', NULL, N'smc:accion', N'1';
DECLARE @accionesDash TABLE (Objeto nvarchar(300));
INSERT @accionesDash VALUES ('api.Filtro_Guardar'), ('api.Filtro_Eliminar'), ('api.Tablero_Guardar'), ('api.Tablero_Eliminar'),
                            ('api.Widget_Guardar'), ('api.Widget_Eliminar'), ('api.Widget_Mover'), ('api.Tablero_Inicio');
DECLARE @oa nvarchar(300);
DECLARE ca CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto FROM @accionesDash;
OPEN ca; FETCH ca INTO @oa;
WHILE @@FETCH_STATUS = 0 BEGIN EXEC adm.Descripcion_Establecer @Objeto = @oa, @Nombre = N'smc:accion', @Valor = N'1'; FETCH ca INTO @oa; END;
CLOSE ca; DEALLOCATE ca;
EXEC adm.Descripcion_Establecer 'api.Rol_Guardar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Rol_Eliminar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Login', N'MS_Description', N'Nombre de usuario para iniciar sesión (p. ej. mbravo)';
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Roles', N'MS_Description', N'Separados por coma, p. ej. Consulta o Administrador. Al editar, vacío = conservar los roles actuales';
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Activo', N'MS_Description', N'No = no puede entrar (se conserva su historial). Al editar, vacío = no cambiar';
EXEC adm.Descripcion_Establecer 'api.Rol_Guardar', '@Permisos', N'MS_Description', N'Separados por coma: lectura (todas las consultas), admin (toda la administración), usuario (tableros, filtros y consultas compartidas) o una opción (ver Permisos por opción). Al editar, vacío = conservar los permisos actuales';
EXEC adm.Descripcion_Establecer 'api.Rol_Opcion_Establecer', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Rol_Opcion_Establecer', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Sync_Resumen', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Mi_Usuario', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Permisos_Matriz', NULL, N'smc:resultados', N'Roles|Opciones del menú|Permisos concedidos';

-- Opciones de menú de varias pantallas: se conceden juntas (seg.fn_Opciones les da título). Todas son pantallas propias
-- de la interfaz, por eso no salen en el menú generado.
DECLARE @opciones TABLE (Objeto nvarchar(300), Opcion nvarchar(100));
INSERT @opciones VALUES
 ('api.Tableros_Listar', N'tableros'), ('api.Tablero_Obtener', N'tableros'), ('api.Tablero_Inicio', N'tableros'),
 ('api.Tablero_Guardar', N'tableros.editar'), ('api.Tablero_Eliminar', N'tableros.editar'), ('api.Widget_Guardar', N'tableros.editar'),
 ('api.Widget_Eliminar', N'tableros.editar'), ('api.Widget_Mover', N'tableros.editar'),
 ('api.Destinatarios_Listar', N'tableros.editar'),
 ('api.Sprints_Listar', N'listas'), ('api.Epicas_Listar', N'listas'), ('api.Personas_Listar', N'listas'),
 ('api.ProyectosSync_Listar', N'sync.proyectos'), ('api.ProyectoSync_Establecer', N'sync.proyectos'), ('api.ProyectosSync_Nuevos_Guardar', N'sync.proyectos'),
 ('api.Filtros_Listar', N'filtros'), ('api.Filtro_Guardar', N'filtros'), ('api.Filtro_Eliminar', N'filtros'),
 ('api.Issues_Consultar', N'busqueda_avanzada'), ('api.Issues_Campos', N'busqueda_avanzada'), ('api.Issues_Valores', N'busqueda_avanzada'),
 ('api.Issues_Resumir', N'busqueda_avanzada'),
 ('api.ConsultasPersonalizadas_Listar', N'consultas_personalizadas'), ('api.ConsultaPersonalizada_Obtener', N'consultas_personalizadas'),
 ('api.ConsultaPersonalizada_Ejecutar', N'consultas_personalizadas');
DECLARE @oo nvarchar(300), @op nvarchar(100);
DECLARE co CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto, Opcion FROM @opciones;
OPEN co; FETCH co INTO @oo, @op;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC adm.Descripcion_Establecer @Objeto = @oo, @Nombre = N'smc:opcion', @Valor = @op;
    -- Se ven en el menú solo las pantallas principales que no son de "usuario" (búsqueda avanzada, proyectos a sincronizar).
    IF @oo NOT IN (N'api.Issues_Consultar', N'api.ProyectosSync_Listar') EXEC adm.Descripcion_Establecer @Objeto = @oo, @Nombre = N'smc:oculto', @Valor = N'1';
    FETCH co INTO @oo, @op;
END;
CLOSE co; DEALLOCATE co;
EXEC adm.Descripcion_Establecer 'api.Aviso_Atender', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Mapeo_Establecer', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.ProyectoSync_Establecer', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.ProyectosSync_Nuevos_Guardar', NULL, N'smc:accion', N'1';

EXEC adm.Descripcion_Establecer 'api.Issues_Campos', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Issues_Valores', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Issues_Resumir', NULL, N'smc:oculto', N'1';

EXEC adm.Descripcion_Establecer 'api.Issue_Detalle', NULL, N'smc:resultados', N'Datos del issue|Campos personalizados|Tiempo registrado|SLA|Historial de estados|Comentarios';
EXEC adm.Descripcion_Establecer 'api.Sync_Estado', NULL, N'smc:resultados', N'Resumen por fuente|Detalle por entidad';

-- Valores permitidos (la interfaz muestra una lista): valor=Etiqueta|...
DECLARE @tipoProyecto nvarchar(200) = N'software=Scrum|service_desk=Mesa de ayuda|business=Negocio';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Proyectos_Listar', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Categoria', N'smc:opciones', N'new=Por hacer|indeterminate=En curso|done=Terminado';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Origen', N'smc:opciones', N'manual=Registradas por personas|automatico=Automáticas (Automation for Jira)';
EXEC adm.Descripcion_Establecer 'api.Sprint_Avance', '@Estado', N'smc:opciones', N'active=Activo|closed=Cerrado|future=Futuro';
EXEC adm.Descripcion_Establecer 'api.Horas_PorSprint', '@Estado', N'smc:opciones', N'active=Activo|closed=Cerrado|future=Futuro';
EXEC adm.Descripcion_Establecer 'api.Epicas_Avance', '@Categoria', N'smc:opciones', N'new=Por hacer|indeterminate=En curso|done=Terminada';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', NULL, N'smc:resultados', N'Resumen|Proyectos, épicas, tareas y subtareas';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@Nivel', N'smc:opciones', N'tarea=Tareas e historias|epica=Épicas';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@Epica', N'MS_Description', N'Clave de una épica (p. ej. SSM26-56).';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@Nivel', N'MS_Description', N'Vacío = tareas e historias (las épicas se comparan aparte para no contar dos veces).';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@Sprint', N'MS_Description', N'Elija el sprint (elija antes el proyecto para ver solo los suyos)';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@Responsable', N'MS_Description', N'Responsable de la tarea';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@SoloExcedidas', N'MS_Description', N'Solo los que registraron más horas de las estimadas.';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', '@Detalle', N'MS_Description', N'No = solo el resumen.';
EXEC adm.Descripcion_Establecer 'api.Epicas_Avance', '@Texto', N'MS_Description', N'Parte de la clave o del resumen de la épica.';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Epica', N'MS_Description', N'Clave de una épica (p. ej. SSM26-56): solo su tiempo, el de sus tareas y subtareas.';
EXEC adm.Descripcion_Establecer 'api.Horas_PorSprint', '@Sprint', N'MS_Description', N'Elija el sprint (elija antes el proyecto para ver solo los suyos)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorSprintArbol', '@Estado', N'smc:opciones', N'active=Activo|closed=Cerrado|future=Futuro';
EXEC adm.Descripcion_Establecer 'api.Horas_PorSprintArbol', NULL, N'smc:resultados', N'Sprints, personas, tareas y subtareas';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Proyecto', N'MS_Description', N'Vacío = todos los proyectos';
EXEC adm.Descripcion_Establecer 'api.Avisos_Listar', '@Nivel', N'smc:opciones', N'info=Información|advertencia=Advertencia|error=Error';

EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Proyecto', N'MS_Description', N'Clave del proyecto (p. ej. SMC26)';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Texto', N'MS_Description', N'Busca en el resumen o por clave exacta';
EXEC adm.Descripcion_Establecer 'api.Sla_EnRiesgo', '@Horas', N'MS_Description', N'Vence en las próximas N horas (4 por omisión)';
EXEC adm.Descripcion_Establecer 'api.Sla_EnRiesgo', '@DiasVencido', N'MS_Description', N'Incluye lo vencido en los últimos N días (7 por omisión)';
EXEC adm.Descripcion_Establecer 'api.Sla_Resumen', '@TicketsSinSla', N'MS_Description', N'Sí = muestra también los tickets que quedaron sin SLA';
EXEC adm.Descripcion_Establecer 'api.Sla_Resumen', NULL, N'smc:resultados', N'Cumplimiento por SLA|Tickets sin SLA';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Desde', N'MS_Description', N'Fecha inicial (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Hasta', N'MS_Description', N'Fecha final (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Origen', N'MS_Description', N'Vacío = ambas';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', '@Origen', N'smc:opciones', N'manual=Registradas por personas|automatico=Automáticas (Automation for Jira)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', '@Desde', N'MS_Description', N'Fecha inicial (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', '@Hasta', N'MS_Description', N'Fecha final (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', '@Origen', N'MS_Description', N'Vacío = ambas';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', NULL, N'smc:resultados', N'Personas, proyectos, épicas, tareas y subtareas';

-- Consultas personalizadas, clientes y configuración de la sincronización.
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Guardar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Eliminar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Usuario_Organizaciones_Guardar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Sync_Frecuencia_Guardar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Sync_Antiguedad_Guardar', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultasPersonalizadas_Listar', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Obtener', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Ejecutar', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Guardar', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Obtener', NULL, N'smc:resultados', N'Consulta|Campos';
EXEC adm.Descripcion_Establecer 'api.ConsultaPersonalizada_Eliminar', '@ConsultaId', N'MS_Description', N'Número de la consulta (aparece en Consultas personalizadas).';
EXEC adm.Descripcion_Establecer 'api.Usuario_Organizaciones_Guardar', '@Login', N'MS_Description', N'Usuario externo (cliente).';
EXEC adm.Descripcion_Establecer 'api.Usuario_Organizaciones_Guardar', '@Organizaciones', N'MS_Description', N'Nombres exactos separados por | (vea Organizaciones de mesa de ayuda). Vacío = no ve tickets.';
EXEC adm.Descripcion_Establecer 'api.Sync_Frecuencia_Guardar', '@Entidad', N'smc:opciones', N'issue=Issues|worklog=Tiempo registrado|worklog_eliminado=Tiempo eliminado|changelog=Historial|comentario=Comentarios|sla=SLA|campo=Campos|estado=Estados|proyecto=Proyectos';
EXEC adm.Descripcion_Establecer 'api.Sync_Frecuencia_Guardar', '@FrecuenciaMin', N'MS_Description', N'Minutos entre sincronizaciones (1 a 10 080). El worker lo toma en su siguiente ciclo.';
EXEC adm.Descripcion_Establecer 'api.Sync_Frecuencia_Guardar', '@Fuente', N'MS_Description', N'Código de la instancia de Jira (p. ej. smco).';
EXEC adm.Descripcion_Establecer 'api.Sync_Antiguedad_Guardar', '@Fuente', N'MS_Description', N'Código de la instancia de Jira (p. ej. smco).';
EXEC adm.Descripcion_Establecer 'api.Sync_Antiguedad_Guardar', '@MaxAntiguedadMin', N'MS_Description', N'Margen en minutos: un dato está atrasado si lleva más que su frecuencia más este margen (5 a 10 080).';
EXEC adm.Descripcion_Establecer 'api.Rol_Guardar', '@EsExterno', N'MS_Description', N'Sí = rol de clientes: solo consultas personalizadas, con los tickets de su organización.';
GO
