/* Llaves foráneas en un solo lugar, después de crear TODAS las tablas (así el orden de 03_Tablas no importa).
   Decisión: ops.Issue NO tiene FK a Proyecto/Estado/Usuario. Jira puede entregar un issue antes que
   el catálogo de su estado o proyecto; una FK rechazaría el issue y frenaría la sincronización. */
DECLARE @fk TABLE (Nombre sysname, Sql nvarchar(max));
INSERT @fk VALUES
 ('FK_sync_IssuePendiente_Fuente', 'ALTER TABLE sync.IssuePendiente ADD CONSTRAINT FK_sync_IssuePendiente_Fuente FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_cfg_EntidadSync_Fuente', 'ALTER TABLE cfg.EntidadSync ADD CONSTRAINT FK_cfg_EntidadSync_Fuente FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_cfg_MapeoCampo_Fuente',  'ALTER TABLE cfg.MapeoCampo  ADD CONSTRAINT FK_cfg_MapeoCampo_Fuente  FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_cfg_MapeoCampo_Rol',     'ALTER TABLE cfg.MapeoCampo  ADD CONSTRAINT FK_cfg_MapeoCampo_Rol     FOREIGN KEY (Rol) REFERENCES cfg.RolCampo (Rol);'),
 ('FK_cfg_ProyectoExcluido_Fuente', 'ALTER TABLE cfg.ProyectoExcluido ADD CONSTRAINT FK_cfg_ProyectoExcluido_Fuente FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_meta_CampoJira_Fuente',  'ALTER TABLE meta.CampoJira  ADD CONSTRAINT FK_meta_CampoJira_Fuente  FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_raw_Documento_Fuente',   'ALTER TABLE raw.Documento   ADD CONSTRAINT FK_raw_Documento_Fuente   FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_sync_Ejecucion_Fuente',  'ALTER TABLE sync.Ejecucion  ADD CONSTRAINT FK_sync_Ejecucion_Fuente  FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_sync_MarcaAgua_Fuente',  'ALTER TABLE sync.MarcaAgua  ADD CONSTRAINT FK_sync_MarcaAgua_Fuente  FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_sync_Candado_Fuente',    'ALTER TABLE sync.Candado    ADD CONSTRAINT FK_sync_Candado_Fuente    FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_ops_Proyecto_Fuente',    'ALTER TABLE ops.Proyecto    ADD CONSTRAINT FK_ops_Proyecto_Fuente    FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_ops_Issue_Fuente',       'ALTER TABLE ops.Issue       ADD CONSTRAINT FK_ops_Issue_Fuente       FOREIGN KEY (FuenteId) REFERENCES cfg.Fuente (FuenteId);'),
 ('FK_ops_IssueCampoValor_Issue', 'ALTER TABLE ops.IssueCampoValor ADD CONSTRAINT FK_ops_IssueCampoValor_Issue FOREIGN KEY (IssueSk) REFERENCES ops.Issue (IssueSk) ON DELETE CASCADE;'),
 ('FK_ops_IssueCambio_Issue',  'ALTER TABLE ops.IssueCambio ADD CONSTRAINT FK_ops_IssueCambio_Issue  FOREIGN KEY (IssueSk) REFERENCES ops.Issue (IssueSk) ON DELETE CASCADE;'),
 ('FK_ops_IssueSprint_Issue',  'ALTER TABLE ops.IssueSprint ADD CONSTRAINT FK_ops_IssueSprint_Issue  FOREIGN KEY (IssueSk) REFERENCES ops.Issue (IssueSk) ON DELETE CASCADE;'),
 ('FK_seg_UsuarioRol_Usuario', 'ALTER TABLE seg.UsuarioRol ADD CONSTRAINT FK_seg_UsuarioRol_Usuario FOREIGN KEY (UsuarioId) REFERENCES seg.Usuario (UsuarioId) ON DELETE CASCADE;'),
 ('FK_seg_UsuarioRol_Rol',     'ALTER TABLE seg.UsuarioRol ADD CONSTRAINT FK_seg_UsuarioRol_Rol     FOREIGN KEY (RolId) REFERENCES seg.Rol (RolId);'),
 ('FK_seg_RolPermiso_Rol',     'ALTER TABLE seg.RolPermiso ADD CONSTRAINT FK_seg_RolPermiso_Rol     FOREIGN KEY (RolId) REFERENCES seg.Rol (RolId) ON DELETE CASCADE;'),
 ('FK_dash_Filtro_Propietario',    'ALTER TABLE dash.Filtro ADD CONSTRAINT FK_dash_Filtro_Propietario FOREIGN KEY (PropietarioId) REFERENCES seg.Usuario (UsuarioId);'),
 ('FK_dash_Tablero_Propietario',   'ALTER TABLE dash.Tablero ADD CONSTRAINT FK_dash_Tablero_Propietario FOREIGN KEY (PropietarioId) REFERENCES seg.Usuario (UsuarioId);'),
 ('FK_dash_TableroCompartido_Tablero', 'ALTER TABLE dash.TableroCompartido ADD CONSTRAINT FK_dash_TableroCompartido_Tablero FOREIGN KEY (TableroId) REFERENCES dash.Tablero (TableroId) ON DELETE CASCADE;'),
 ('FK_dash_Widget_Tablero',        'ALTER TABLE dash.Widget ADD CONSTRAINT FK_dash_Widget_Tablero FOREIGN KEY (TableroId) REFERENCES dash.Tablero (TableroId) ON DELETE CASCADE;'),
 ('FK_dash_Widget_Filtro',         'ALTER TABLE dash.Widget ADD CONSTRAINT FK_dash_Widget_Filtro FOREIGN KEY (FiltroId) REFERENCES dash.Filtro (FiltroId);'),
 ('FK_dash_Preferencia_Usuario',   'ALTER TABLE dash.Preferencia ADD CONSTRAINT FK_dash_Preferencia_Usuario FOREIGN KEY (UsuarioId) REFERENCES seg.Usuario (UsuarioId) ON DELETE CASCADE;'),
 ('FK_dash_Preferencia_Tablero',   'ALTER TABLE dash.Preferencia ADD CONSTRAINT FK_dash_Preferencia_Tablero FOREIGN KEY (TableroInicioId) REFERENCES dash.Tablero (TableroId) ON DELETE SET NULL;'),
 ('FK_ops_IssueResumen_Issue', 'ALTER TABLE ops.IssueResumen ADD CONSTRAINT FK_ops_IssueResumen_Issue FOREIGN KEY (IssueSk) REFERENCES ops.Issue (IssueSk) ON DELETE CASCADE;'),
 ('FK_ops_IssueSla_Issue',     'ALTER TABLE ops.IssueSla    ADD CONSTRAINT FK_ops_IssueSla_Issue     FOREIGN KEY (IssueSk) REFERENCES ops.Issue (IssueSk) ON DELETE CASCADE;');

DECLARE @n sysname, @s nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Nombre, Sql FROM @fk;
OPEN c; FETCH c INTO @n, @s;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @n) EXEC (@s);
    FETCH c INTO @n, @s;
END;
CLOSE c; DEALLOCATE c;
GO
