/* Índices no agrupados. Las llaves primarias y únicas ya se crearon con cada tabla. */
IF INDEXPROPERTY(OBJECT_ID('raw.Documento'), 'IX_raw_Documento_Pendientes', 'IndexId') IS NULL
    CREATE INDEX IX_raw_Documento_Pendientes ON raw.Documento (FuenteId, Entidad, Intentos) WHERE Procesado = 0;
IF INDEXPROPERTY(OBJECT_ID('raw.Documento'), 'IX_raw_Documento_Lote', 'IndexId') IS NULL
    CREATE INDEX IX_raw_Documento_Lote ON raw.Documento (LoteId) INCLUDE (Actualizado);

IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Clave', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Clave ON ops.Issue (Clave) INCLUDE (FuenteId);
-- Hijos de un issue (tareas de una épica, subtareas de una tarea): para acumular horas y avance.
IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Padre', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Padre ON ops.Issue (FuenteId, PadreId) INCLUDE (IssueId, Clave, EsSubtarea, NivelJerarquia, Eliminado);
IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Proyecto', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Proyecto ON ops.Issue (FuenteId, ProyectoId, Creado) INCLUDE (CategoriaEstado, ResponsableId, Eliminado);
IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Actualizado', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Actualizado ON ops.Issue (Actualizado);

IF INDEXPROPERTY(OBJECT_ID('ops.IssueCampoValor'), 'IX_ops_IssueCampoValor_Campo', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueCampoValor_Campo ON ops.IssueCampoValor (CampoId, ValorId) INCLUDE (ValorTexto, ValorNumero);

-- Historial de un campo de un issue (atribución de horas automáticas por responsable).
IF INDEXPROPERTY(OBJECT_ID('ops.IssueCambio'), 'IX_ops_IssueCambio_Campo', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueCambio_Campo ON ops.IssueCambio (IssueSk, CampoId, Fecha) INCLUDE (Desde, Hacia, HistoriaId, Orden);
IF INDEXPROPERTY(OBJECT_ID('ops.Comentario'), 'IX_ops_Comentario_Issue', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Comentario_Issue ON ops.Comentario (FuenteId, IssueId) INCLUDE (Creado, AutorId, Publico, Eliminado);
IF INDEXPROPERTY(OBJECT_ID('ops.IssueResumen'), 'IX_ops_IssueResumen_Epica', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueResumen_Epica ON ops.IssueResumen (FuenteId, EpicaIssueId);
IF INDEXPROPERTY(OBJECT_ID('ops.IssueCambio'), 'IX_ops_IssueCambio_Issue', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueCambio_Issue ON ops.IssueCambio (IssueSk, Fecha) INCLUDE (CampoId, Hacia, HaciaTexto);

IF INDEXPROPERTY(OBJECT_ID('ops.IssueSprint'), 'IX_ops_IssueSprint_Sprint', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueSprint_Sprint ON ops.IssueSprint (FuenteId, SprintId);

IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_IssueDet', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Worklog_IssueDet ON ops.Worklog (FuenteId, IssueId) INCLUDE (Inicio, AutorId, Segundos, Eliminado, EsAutomatico, EsCopia, AtribuidoAId, MetodoAtribucion);
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_InicioDet', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Worklog_InicioDet ON ops.Worklog (Inicio) INCLUDE (FuenteId, IssueId, AutorId, Segundos, Eliminado, EsAutomatico, EsCopia, AtribuidoAId, MetodoAtribucion);
-- Búsqueda del original de una copia automática: mismo tiempo, creado casi al mismo momento (sync.Worklog_Atribuir).
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_Copia', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Worklog_Copia ON ops.Worklog (FuenteId, Segundos, Creado) INCLUDE (IssueId, AutorId, EsAutomatico, Eliminado);

IF INDEXPROPERTY(OBJECT_ID('sync.Ejecucion'), 'IX_sync_Ejecucion_Fuente', 'IndexId') IS NULL
    CREATE INDEX IX_sync_Ejecucion_Fuente ON sync.Ejecucion (FuenteId, Entidad, Inicio DESC) INCLUDE (Estado, Fin);
IF INDEXPROPERTY(OBJECT_ID('sync.Solicitud'), 'IX_sync_Solicitud_Pendiente', 'IndexId') IS NULL
    CREATE INDEX IX_sync_Solicitud_Pendiente ON sync.Solicitud (Fecha) WHERE Estado = 'pendiente';
IF INDEXPROPERTY(OBJECT_ID('sync.Evento'), 'IX_sync_Evento_Abiertos', 'IndexId') IS NULL
    CREATE INDEX IX_sync_Evento_Abiertos ON sync.Evento (Fecha DESC) INCLUDE (Nivel, Codigo, FuenteId) WHERE Atendido = 0;
IF INDEXPROPERTY(OBJECT_ID('seg.Auditoria'), 'IX_seg_Auditoria_Fecha', 'IndexId') IS NULL
    CREATE INDEX IX_seg_Auditoria_Fecha ON seg.Auditoria (Fecha DESC) INCLUDE (Usuario, Accion);
IF INDEXPROPERTY(OBJECT_ID('dash.Widget'), 'IX_dash_Widget_Tablero', 'IndexId') IS NULL
    CREATE INDEX IX_dash_Widget_Tablero ON dash.Widget (TableroId, Orden);
IF INDEXPROPERTY(OBJECT_ID('dash.Widget'), 'IX_dash_Widget_Filtro', 'IndexId') IS NULL
    CREATE INDEX IX_dash_Widget_Filtro ON dash.Widget (FiltroId);
GO
