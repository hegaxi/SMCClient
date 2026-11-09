/* Trabajo pendiente por issue, persistido en la base (no en la memoria del worker):
   - changelog / sla (entidades 'dependiente'): issues nuevos o que cambiaron y cuyo historial o SLA aún no se trae.
     Los encola sync.Procesar_Issues; el worker los borra (sync.IssuePendiente_Completar) solo cuando ya los guardó en raw.
     Si el worker se cae o Jira falla, siguen aquí y se piden en la siguiente corrida.
   - padre: claves de padres o épicas que los issues mencionan y que no están en ops.Issue (p. ej. épicas sin cambios
     desde antes de la carga inicial). Los encola y los quita sync.Padres_Pendientes. */
IF OBJECT_ID('sync.IssuePendiente', 'U') IS NULL
CREATE TABLE sync.IssuePendiente (
    FuenteId      int            NOT NULL,
    Entidad       varchar(40)    NOT NULL,      -- changelog | sla | padre
    IssueId       varchar(50)    NOT NULL,      -- id de Jira (para 'padre': la clave, que es lo que se conoce)
    Clave         varchar(50)    NULL,
    TipoProyecto  varchar(30)    NULL,
    Agregado      datetimeoffset(3) NOT NULL CONSTRAINT DF_sync_IssuePendiente_Agregado DEFAULT SYSDATETIMEOFFSET(),
    Intentos      int            NOT NULL CONSTRAINT DF_sync_IssuePendiente_Intentos DEFAULT 0,
    UltimoIntento datetimeoffset(3) NULL,
    CONSTRAINT PK_sync_IssuePendiente PRIMARY KEY (FuenteId, Entidad, IssueId)
);
GO
