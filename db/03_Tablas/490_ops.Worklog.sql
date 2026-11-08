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
    CONSTRAINT PK_ops_Worklog PRIMARY KEY (FuenteId, WorklogId)
);
GO
