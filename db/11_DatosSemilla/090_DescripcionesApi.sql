/* Metadatos que lee el controlador único para construir la interfaz y autorizar:
   MS_Description  descripción que ve el usuario
   smc:permiso     lectura | admin (el controlador exige el rol de aplicación correspondiente)
   smc:exentoSync  1 = se puede ejecutar aunque los datos no estén sincronizados */
DECLARE @p TABLE (Objeto nvarchar(300), Descripcion nvarchar(400), Permiso varchar(10), Exento char(1));
INSERT @p VALUES
 ('api.Sync_Estado',      N'Estado de la sincronización con Jira.',                         'lectura', '1'),
 ('api.Sync_Solicitar',   N'Solicita una sincronización inmediata.',                        'lectura', '1'),
 ('api.Avisos_Listar',    N'Avisos de la sincronización (campos nuevos, eliminados, errores).', 'admin', '1'),
 ('api.Aviso_Atender',    N'Marca un aviso como atendido.',                                 'admin',   '1'),
 ('api.Campos_Listar',    N'Catálogo de campos de Jira y su rol en el modelo.',             'lectura', '1'),
 ('api.Mapeos_Listar',    N'Roles del modelo y el campo de Jira asignado a cada uno.',      'admin',   '1'),
 ('api.Mapeo_Establecer', N'Asigna manualmente el campo de Jira de un rol.',                'admin',   '1'),
 ('api.Proyectos_Listar', N'Proyectos Scrum y de mesa de ayuda.',                           'lectura', '0'),
 ('api.Issues_Buscar',    N'Búsqueda de historias y tickets.',                              'lectura', '0'),
 ('api.Issue_Detalle',    N'Detalle de un issue: campos, worklogs, SLA e historial.',       'lectura', '0'),
 ('api.Horas_PorPersona', N'Horas por persona y proyecto: registradas por personas y automáticas (Automation for Jira) por separado.',                      'lectura', '0'),
 ('api.Sla_Resumen',      N'Cumplimiento de SLA por proyecto.',                             'lectura', '0'),
 ('api.Sla_EnRiesgo',     N'Tickets con SLA por vencer o vencido.',                         'lectura', '0'),
 ('api.Sprint_Avance',    N'Avance por sprint (issues, story points y horas).',             'lectura', '0');

DECLARE @o nvarchar(300), @d nvarchar(400), @pe varchar(10), @e char(1);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto, Descripcion, Permiso, Exento FROM @p;
OPEN c; FETCH c INTO @o, @d, @pe, @e;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Valor = @d;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:permiso', @Valor = @pe;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:exentoSync', @Valor = @e;
    FETCH c INTO @o, @d, @pe, @e;
END;
CLOSE c; DEALLOCATE c;

EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Proyecto', N'MS_Description', N'Clave del proyecto (p. ej. SMC26)';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@TipoProyecto', N'MS_Description', N'software (Scrum) o service_desk (mesa de ayuda)';
EXEC adm.Descripcion_Establecer 'api.Issues_Buscar', '@Categoria', N'MS_Description', N'new, indeterminate o done';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Desde', N'MS_Description', N'Fecha inicial (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Hasta', N'MS_Description', N'Fecha final (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersona', '@Origen', N'MS_Description', N'manual (registradas por personas), automatico (Automation for Jira) o vacío para ambas';
GO
