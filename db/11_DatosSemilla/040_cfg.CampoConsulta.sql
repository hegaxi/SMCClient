/* Campos estándar del buscador. Se reescriben en cada despliegue (es configuración de código, no del usuario). */
MERGE cfg.CampoConsulta AS t
USING (VALUES
 ('clave',          N'Clave',                  'texto',   N'i.Clave',                         NULL, N'Clave',            1, 1,  10),
 ('texto',          N'Texto (clave o resumen)', 'texto',  N'CONCAT(i.Clave, N'' '', i.Resumen)', NULL, N'Texto',       0, 0,  15),
 ('resumen',        N'Resumen',                'texto',   N'i.Resumen',                       NULL, N'Resumen',          1, 1,  20),
 ('proyecto',       N'Proyecto',               'lista',   N'i.ProyectoClave',                 NULL, N'Proyecto',         1, 1,  30),
 ('tipo_proyecto',  N'Tipo de proyecto',       'lista',   N'CASE i.TipoProyecto WHEN ''software'' THEN N''Scrum'' WHEN ''service_desk'' THEN N''Mesa de ayuda'' WHEN ''business'' THEN N''Negocio'' ELSE i.TipoProyecto END', NULL, N'TipoProyecto', 1, 0, 35),
 ('tipo',           N'Tipo',                   'lista',   N'i.TipoIssue',                     NULL, N'Tipo',             1, 1,  40),
 ('es_subtarea',    N'Es subtarea',            'bit',     N'i.EsSubtarea',                    NULL, N'EsSubtarea',       1, 0,  45),
 ('estado',         N'Estado',                 'lista',   N'i.Estado',                        NULL, N'Estado',           1, 1,  50),
 ('categoria',      N'Categoría de estado',    'lista',   N'CASE i.CategoriaEstado WHEN ''new'' THEN N''Por hacer'' WHEN ''indeterminate'' THEN N''En curso'' WHEN ''done'' THEN N''Terminado'' ELSE i.CategoriaEstado END', NULL, N'Categoria', 1, 0, 55),
 ('prioridad',      N'Prioridad',              'lista',   N'i.Prioridad',                     NULL, N'Prioridad',        1, 1,  60),
 ('resolucion',     N'Resolución',             'lista',   N'i.Resolucion',                    NULL, N'Resolucion',       1, 0,  65),
 ('responsable',    N'Responsable',            'usuario', N'i.Responsable',                   NULL, N'Responsable',      1, 1,  70),
 ('informante',     N'Informante',             'usuario', N'i.Informante',                    NULL, N'Informante',       1, 0,  75),
 ('tipo_solicitud', N'Tipo de solicitud',      'lista',   N'i.TipoSolicitud',                 NULL, N'TipoSolicitud',    1, 0,  80),
 ('padre',          N'Padre',                  'texto',   N'i.PadreClave',                    NULL, N'Padre',            1, 0,  85),
 ('sprint',         N'Sprint',                 'lista',   NULL, N'SELECT s.Nombre FROM ops.IssueSprint x JOIN ops.Sprint s ON s.FuenteId = x.FuenteId AND s.SprintId = x.SprintId WHERE x.IssueSk = i.IssueSk', N'Sprint', 1, 0, 90),
 ('etiquetas',      N'Etiquetas',              'lista',   NULL, N'SELECT x.ValorTexto FROM ops.IssueCampoValor x WHERE x.IssueSk = i.IssueSk AND x.CampoId = ''labels''', N'Etiquetas', 1, 0, 95),
 ('componentes',    N'Componentes',            'lista',   NULL, N'SELECT x.ValorTexto FROM ops.IssueCampoValor x WHERE x.IssueSk = i.IssueSk AND x.CampoId = ''components''', N'Componentes', 1, 0, 96),
 ('story_points',   N'Story points',           'numero',  N'i.StoryPoints',                   NULL, N'StoryPoints',      1, 0, 100),
 ('horas',          N'Horas invertidas (Jira)',       'numero',  N'CAST(i.TiempoInvertidoSeg / 3600.0 AS decimal(12,2))', NULL, N'HorasInvertidas', 1, 0, 105),
 ('horas_registradas', N'Horas registradas (con subtareas)', 'numero', N'(SELECT h.HorasRegistradas FROM rpt.fn_HorasIssue(i.FuenteId, i.IssueId, i.Clave) h)', NULL, N'HorasRegistradas', 1, 0, 102),
 ('horas_automaticas', N'Horas automáticas (con subtareas)', 'numero', N'(SELECT h.HorasAutomaticas FROM rpt.fn_HorasIssue(i.FuenteId, i.IssueId, i.Clave) h)', NULL, N'HorasAutomaticas', 1, 0, 103),
 ('horas_estimadas',N'Horas estimadas',        'numero',  N'CAST(i.EstimacionOriginalSeg / 3600.0 AS decimal(12,2))', NULL, N'HorasEstimadas', 1, 0, 106),
 ('creado',         N'Creado',                 'fecha',   N'i.Creado',                        NULL, N'Creado',           1, 0, 110),
 ('actualizado',    N'Actualizado',            'fecha',   N'i.Actualizado',                   NULL, N'Actualizado',      1, 1, 115),
 ('resuelto',       N'Resuelto',               'fecha',   N'i.Resuelto',                      NULL, N'Resuelto',         1, 0, 120),
 ('vencimiento',    N'Vencimiento',            'fecha',   N'i.Vencimiento',                   NULL, N'Vencimiento',      1, 0, 125),
 ('registro_persona', N'Registró tiempo (persona)', 'usuario', NULL, N'SELECT DISTINCT COALESCE(u.Nombre, w.AutorId) FROM ops.Worklog w LEFT JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId WHERE w.FuenteId = i.FuenteId AND w.IssueId = i.IssueId AND w.Eliminado = 0 AND ISNULL(u.TipoCuenta, '''') <> ''app''', N'RegistroTiempoPersona', 1, 0, 126),
 ('registro_fecha', N'Fecha de registro de tiempo', 'fecha', NULL, N'SELECT w.Inicio FROM ops.Worklog w WHERE w.FuenteId = i.FuenteId AND w.IssueId = i.IssueId AND w.Eliminado = 0', N'FechaRegistroTiempo', 0, 0, 127),
 ('abierto',        N'Abierto',                'bit',     N'i.Abierto',                       NULL, N'Abierto',          1, 0, 130),
 ('sla_incumplido', N'SLA incumplido',         'bit',     N'CAST(CASE WHEN EXISTS (SELECT 1 FROM rpt.vSla s WHERE s.IssueSk = i.IssueSk AND s.Incumplido = 1) THEN 1 ELSE 0 END AS bit)', NULL, N'SlaIncumplido', 1, 0, 135)
) AS s (Clave, Etiqueta, Tipo, Expresion, ExpresionMulti, Alias, EsColumna, ColumnaPredeterminada, Orden)
ON t.Clave = s.Clave
WHEN MATCHED THEN UPDATE SET Etiqueta = s.Etiqueta, Tipo = s.Tipo, Expresion = s.Expresion, ExpresionMulti = s.ExpresionMulti, Alias = s.Alias,
                             EsColumna = s.EsColumna, ColumnaPredeterminada = s.ColumnaPredeterminada, Orden = s.Orden
WHEN NOT MATCHED THEN INSERT (Clave, Etiqueta, Tipo, Expresion, ExpresionMulti, Alias, EsColumna, ColumnaPredeterminada, Orden)
     VALUES (s.Clave, s.Etiqueta, s.Tipo, s.Expresion, s.ExpresionMulti, s.Alias, s.EsColumna, s.ColumnaPredeterminada, s.Orden)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
GO
