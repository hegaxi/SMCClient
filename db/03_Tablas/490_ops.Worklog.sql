/* Tiempo invertido. Se obtiene aparte del issue porque la búsqueda solo trae 20 worklogs por issue. */
IF OBJECT_ID('ops.Worklog', 'U') IS NULL
CREATE TABLE ops.Worklog (
    FuenteId         int            NOT NULL,
    WorklogId        varchar(30)    NOT NULL,
    IssueId          varchar(30)    NOT NULL,   -- id de Jira del issue (se une con ops.Issue por FuenteId+IssueId)
    AutorId          varchar(128)   NULL,
    ActualizadoPorId varchar(128)   NULL,
    Inicio           datetimeoffset(3) NOT NULL,
    Segundos         int            NOT NULL,
    Creado           datetimeoffset(3) NULL,
    Actualizado      datetimeoffset(3) NULL,
    Eliminado        bit            NOT NULL CONSTRAINT DF_ops_Worklog_Eliminado DEFAULT 0,
    -- Calculados al integrar (sync.Worklog_Atribuir); ver rpt.vWorklog.
    EsAutomatico     bit            NULL,       -- 1 = lo registró una app (Automation for Jira)
    AtribuidoAId     varchar(128)   NULL,       -- persona a la que se atribuye (automáticos: responsable del issue ese día)
    MetodoAtribucion varchar(20)    NULL,       -- autor | historial | responsable_actual
    CONSTRAINT PK_ops_Worklog PRIMARY KEY (FuenteId, WorklogId)
);
GO
