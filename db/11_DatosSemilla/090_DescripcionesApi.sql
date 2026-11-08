/* Metadatos que lee el controlador único para construir la interfaz y autorizar:
   smc:titulo      nombre corto para el menú
   MS_Description  descripción que ve el usuario
   smc:permiso     usuario (cualquier usuario activo) | lectura | admin. Quién tiene cada categoría lo deciden
                   los roles en seg.RolPermiso (ver seg.Permisos_Usuario)
   smc:exentoSync  1 = se puede ejecutar aunque los datos no estén sincronizados
   smc:accion      1 = modifica algo (la interfaz nunca lo ejecuta solo al abrirlo; pide confirmar)
   smc:resultados  títulos de cada conjunto de resultados, separados por '|'
   smc:oculto      1 = no aparece en el menú (lo usa una pantalla propia de la interfaz)
   smc:opciones    (en un parámetro) valores permitidos: valor=Etiqueta|valor2=Etiqueta2 */
DECLARE @p TABLE (Objeto nvarchar(300), Titulo nvarchar(100), Descripcion nvarchar(400), Permiso varchar(10), Exento char(1));
INSERT @p VALUES
 ('api.Issues_Buscar',    N'Buscar historias y tickets', N'Historias Scrum y tickets de mesa de ayuda con filtros por proyecto, estado, responsable y fechas.', 'lectura', '0'),
 ('api.Issue_Detalle',    N'Detalle de un issue',        N'Datos, campos personalizados, tiempo registrado, SLA e historial de un issue.',                   'lectura', '0'),
 ('api.Horas_PorPersona', N'Horas por persona',          N'Horas por persona y proyecto: registradas por personas y automáticas (Automation for Jira) por separado.', 'lectura', '0'),
 ('api.Sla_Resumen',      N'Cumplimiento de SLA',        N'Cumplimiento de SLA por proyecto para los tickets creados en el periodo.',                      'lectura', '0'),
 ('api.Sla_EnRiesgo',     N'SLA por vencer',             N'Tickets abiertos con un SLA que vence pronto o ya venció.',                                     'lectura', '0'),
 ('api.Sprint_Avance',    N'Avance de sprints',          N'Issues, story points y horas por sprint.',                                                      'lectura', '0'),
 ('api.Proyectos_Listar', N'Proyectos',                  N'Proyectos Scrum y de mesa de ayuda que se sincronizan.',                                        'lectura', '0'),
 ('api.Sync_Estado',      N'Estado de la sincronización', N'Cuándo se sincronizó cada fuente y cada tipo de dato.',                                        'lectura', '1'),
 ('api.Sync_Solicitar',   N'Sincronizar ahora',          N'Pide una sincronización inmediata con Jira.',                                                   'lectura', '1'),
 ('api.Campos_Listar',    N'Campos de Jira',             N'Catálogo de campos de Jira y el rol que cumplen en los reportes.',                              'lectura', '1'),
 ('api.Avisos_Listar',    N'Avisos',                     N'Cambios detectados en Jira (campos nuevos o eliminados) y errores de sincronización.',          'admin',   '1'),
 ('api.Aviso_Atender',    N'Marcar aviso como atendido', N'Marca un aviso como atendido.',                                                                 'admin',   '1'),
 ('api.Mapeos_Listar',    N'Mapeo de campos',            N'Qué campo de Jira alimenta cada dato de los reportes (estado, story points, sprint...).',       'admin',   '1'),
 ('api.Mapeo_Establecer', N'Asignar campo a un dato',    N'Asigna manualmente el campo de Jira de un dato; vacío lo devuelve a automático.',              'admin',   '1'),
 ('api.Mi_Usuario',       N'Mi usuario',                 N'Su usuario y sus roles.',                                                                       'usuario', '1'),
 ('api.Usuarios_Listar',  N'Usuarios',                   N'Usuarios de la aplicación y sus roles.',                                                        'admin',   '1'),
 ('api.Usuario_Guardar',  N'Guardar usuario',            N'Da de alta o modifica un usuario y le asigna roles. La contraseña se asigna en Restablecer contraseña.',                         'admin',   '1'),
 ('api.Roles_Listar',     N'Roles',                      N'Roles y sus permisos.',                                                                         'admin',   '1'),
 ('api.Rol_Guardar',      N'Guardar rol',                N'Crea o modifica un rol y sus permisos.',                                                        'admin',   '1'),
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
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Roles', N'MS_Description', N'Separados por coma, p. ej. Consulta o Administrador';
EXEC adm.Descripcion_Establecer 'api.Usuario_Guardar', '@Activo', N'MS_Description', N'No = no puede entrar (se conserva su historial)';
EXEC adm.Descripcion_Establecer 'api.Rol_Guardar', '@Permisos', N'MS_Description', N'Separados por coma: lectura (todas las consultas), admin (administración) o api.Nombre (un procedimiento)';
EXEC adm.Descripcion_Establecer 'api.Aviso_Atender', NULL, N'smc:accion', N'1';
EXEC adm.Descripcion_Establecer 'api.Mapeo_Establecer', NULL, N'smc:accion', N'1';

EXEC adm.Descripcion_Establecer 'api.Issues_Campos', NULL, N'smc:oculto', N'1';
EXEC adm.Descripcion_Establecer 'api.Issues_Valores', NULL, N'smc:oculto', N'1';

EXEC adm.Descripcion_Establecer 'api.Issue_Detalle', NULL, N'smc:resultados', N'Datos del issue|Campos personalizados|Tiempo registrado|SLA|Historial de estados';
EXEC adm.Descripcion_Establecer 'api.Sync_Estado', NULL, N'smc:resultados', N'Resumen por fuente|Detalle por entidad';

-- Valores permitidos (la interfaz muestra una lista): valor=Etiqueta|...
DECLARE @tipoProyecto nvarchar(200) = N'software=Scrum|service_desk=Mesa de ayuda|business=Negocio';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Proyectos_Listar', '@TipoProyecto', N'smc:opciones', @tipoProyecto;
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Categoria', N'smc:opciones', N'new=Por hacer|indeterminate=En curso|done=Terminado';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Origen', N'smc:opciones', N'manual=Registradas por personas|automatico=Automáticas (Automation for Jira)';
EXEC adm.Descripcion_Establecer 'api.Sprint_Avance', '@Estado', N'smc:opciones', N'active=Activo|closed=Cerrado|future=Futuro';
EXEC adm.Descripcion_Establecer 'api.Avisos_Listar', '@Nivel', N'smc:opciones', N'info=Información|advertencia=Advertencia|error=Error';

EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Proyecto', N'MS_Description', N'Clave del proyecto (p. ej. SMC26)';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Texto', N'MS_Description', N'Busca en el resumen o por clave exacta';
EXEC adm.Descripcion_Establecer 'api.Sla_EnRiesgo', '@Horas', N'MS_Description', N'Vence en las próximas N horas (4 por omisión)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Desde', N'MS_Description', N'Fecha inicial (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Hasta', N'MS_Description', N'Fecha final (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Origen', N'MS_Description', N'Vacío = ambas';
GO
