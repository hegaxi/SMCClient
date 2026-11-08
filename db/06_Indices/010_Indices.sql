/* Índices no agrupados. Las llaves primarias y únicas ya se crearon con cada tabla. */
IF INDEXPROPERTY(OBJECT_ID('raw.Documento'), 'IX_raw_Documento_Pendientes', 'IndexId') IS NULL
    CREATE INDEX IX_raw_Documento_Pendientes ON raw.Documento (FuenteId, Entidad, Intentos) WHERE Procesado = 0;
IF INDEXPROPERTY(OBJECT_ID('raw.Documento'), 'IX_raw_Documento_Lote', 'IndexId') IS NULL
    CREATE INDEX IX_raw_Documento_Lote ON raw.Documento (LoteId) INCLUDE (Actualizado);

IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Clave', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Clave ON ops.Issue (Clave) INCLUDE (FuenteId);
IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Proyecto', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Proyecto ON ops.Issue (FuenteId, ProyectoId, Creado) INCLUDE (CategoriaEstado, ResponsableId, Eliminado);
IF INDEXPROPERTY(OBJECT_ID('ops.Issue'), 'IX_ops_Issue_Actualizado', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Issue_Actualizado ON ops.Issue (Actualizado);

IF INDEXPROPERTY(OBJECT_ID('ops.IssueCampoValor'), 'IX_ops_IssueCampoValor_Campo', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueCampoValor_Campo ON ops.IssueCampoValor (CampoId, ValorId) INCLUDE (ValorTexto, ValorNumero);

IF INDEXPROPERTY(OBJECT_ID('ops.IssueCambio'), 'IX_ops_IssueCambio_Issue', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueCambio_Issue ON ops.IssueCambio (IssueSk, Fecha) INCLUDE (CampoId, Hacia, HaciaTexto);

IF INDEXPROPERTY(OBJECT_ID('ops.IssueSprint'), 'IX_ops_IssueSprint_Sprint', 'IndexId') IS NULL
    CREATE INDEX IX_ops_IssueSprint_Sprint ON ops.IssueSprint (FuenteId, SprintId);

IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_Issue', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Worklog_Issue ON ops.Worklog (FuenteId, IssueId) INCLUDE (Segundos, Eliminado);
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_Inicio', 'IndexId') IS NULL
    CREATE INDEX IX_ops_Worklog_Inicio ON ops.Worklog (Inicio) INCLUDE (FuenteId, IssueId, AutorId, Segundos, Eliminado);

IF INDEXPROPERTY(OBJECT_ID('sync.Ejecucion'), 'IX_sync_Ejecucion_Fuente', 'IndexId') IS NULL
    CREATE INDEX IX_sync_Ejecucion_Fuente ON sync.Ejecucion (FuenteId, Entidad, Inicio DESC) INCLUDE (Estado, Fin);
IF INDEXPROPERTY(OBJECT_ID('sync.Solicitud'), 'IX_sync_Solicitud_Pendiente', 'IndexId') IS NULL
    CREATE INDEX IX_sync_Solicitud_Pendiente ON sync.Solicitud (Fecha) WHERE Estado = 'pendiente';
IF INDEXPROPERTY(OBJECT_ID('sync.Evento'), 'IX_sync_Evento_Abiertos', 'IndexId') IS NULL
    CREATE INDEX IX_sync_Evento_Abiertos ON sync.Evento (Fecha DESC) INCLUDE (Nivel, Codigo, FuenteId) WHERE Atendido = 0;
GO
