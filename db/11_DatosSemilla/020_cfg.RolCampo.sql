/* Roles del modelo canónico y sus reglas para encontrar el campo en Jira.
   Solo inserta los roles que falten (el administrador puede ajustar reglas con UPDATE).
   Reglas de JSM/Jira Software verificadas en smco.atlassian.net:
     Sprint         -> com.pyxis.greenhopper.jira:gh-sprint       (customfield_10020)
     Request Type   -> com.atlassian.servicedesk:vp-origin        (customfield_10010)
     Story points   -> com.pyxis.greenhopper.jira:jsw-story-points o por nombre */
MERGE cfg.RolCampo AS t
USING (VALUES
  ('resumen',             N'Título del issue',                       'texto',  1, 'summary',              NULL,                                          NULL,                                           N'$',              NULL),
  ('proyecto',            N'Proyecto (id y clave)',                  'id',     1, 'project',              NULL,                                          NULL,                                           N'$.id',           N'$.key'),
  ('tipo_issue',          N'Tipo de issue',                          'id',     1, 'issuetype',            NULL,                                          NULL,                                           N'$.id',           N'$.name'),
  ('estado',              N'Estado actual',                          'id',     1, 'status',               NULL,                                          NULL,                                           N'$.id',           N'$.name'),
  ('categoria_estado',    N'Categoría del estado (new/indeterminate/done)', 'texto', 1, 'status',         NULL,                                          NULL,                                           N'$.statusCategory.key', NULL),
  ('prioridad',           N'Prioridad',                              'id',     0, 'priority',             NULL,                                          NULL,                                           N'$.id',           N'$.name'),
  ('resolucion',          N'Resolución',                             'id',     0, 'resolution',           NULL,                                          NULL,                                           N'$.id',           N'$.name'),
  ('responsable',         N'Responsable (assignee)',                 'id',     0, 'assignee',             NULL,                                          NULL,                                           N'$.accountId',    N'$.displayName'),
  ('informante',          N'Informante (reporter)',                  'id',     0, 'reporter',             NULL,                                          NULL,                                           N'$.accountId',    N'$.displayName'),
  ('padre',               N'Issue padre (épica o tarea)',            'id',     0, 'parent',               NULL,                                          NULL,                                           N'$.key',          NULL),
  ('creado',              N'Fecha de creación',                      'fecha',  1, 'created',              NULL,                                          NULL,                                           N'$',              NULL),
  ('actualizado',         N'Fecha de última modificación',           'fecha',  1, 'updated',              NULL,                                          NULL,                                           N'$',              NULL),
  ('resuelto',            N'Fecha de resolución',                    'fecha',  0, 'resolutiondate',       NULL,                                          NULL,                                           N'$',              NULL),
  ('vencimiento',         N'Fecha de vencimiento',                   'fecha',  0, 'duedate',              NULL,                                          NULL,                                           N'$',              NULL),
  ('tiempo_invertido',    N'Tiempo invertido total (segundos)',      'numero', 0, 'timespent',            NULL,                                          NULL,                                           N'$',              NULL),
  ('estimacion_original', N'Estimación original (segundos)',         'numero', 0, 'timeoriginalestimate', NULL,                                          NULL,                                           N'$',              NULL),
  ('estimacion_restante', N'Estimación restante (segundos)',         'numero', 0, 'timeestimate',         NULL,                                          NULL,                                           N'$',              NULL),
  ('sprint',              N'Sprints del issue',                      'id',     0, NULL,                   N'com.pyxis.greenhopper.jira:gh-sprint',       N'Sprint',                                      N'$',              NULL),
  ('story_points',        N'Story points',                           'numero', 0, NULL,                   N'com.pyxis.greenhopper.jira:jsw-story-points', N'Story point estimate|Story Points|Puntos de historia', N'$',     NULL),
  ('tipo_solicitud',      N'Tipo de solicitud de JSM (request type)', 'id',    0, NULL,                   N'com.atlassian.servicedesk:vp-origin',        N'Request Type|Tipo de solicitud',              N'$.requestType.id', N'$.requestType.name'),
  ('prioridad_itil',      N'Prioridad ITIL que fija el objetivo del SLA (urgencia x impacto)', 'numero', 0, NULL, NULL, N'prioridad|Prioridad ITIL|Prioridad SLA', N'$', NULL),
  ('organizacion',        N'Organizaciones (clientes) de JSM',        'texto', 0, NULL,                   N'com.atlassian.servicedesk:sd-customer-organizations', N'Organizations|Organizaciones',        N'$',              NULL)
) AS s (Rol, Descripcion, TipoDato, Obligatorio, ReglaCampoSistema, ReglaTipoCustom, ReglaNombre, RutaValor, RutaTexto)
ON t.Rol = s.Rol
WHEN NOT MATCHED THEN INSERT (Rol, Descripcion, TipoDato, Obligatorio, ReglaCampoSistema, ReglaTipoCustom, ReglaNombre, RutaValor, RutaTexto)
     VALUES (s.Rol, s.Descripcion, s.TipoDato, s.Obligatorio, s.ReglaCampoSistema, s.ReglaTipoCustom, s.ReglaNombre, s.RutaValor, s.RutaTexto);
GO
