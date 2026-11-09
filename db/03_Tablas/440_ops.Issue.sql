/* Modelo canónico de un issue (historia Scrum o ticket de mesa de ayuda; en Jira ambos son issues).
   Cada columna se llena a partir de un ROL (cfg.RolCampo / cfg.MapeoCampo), no de un ID fijo de Jira.
   Agregar una columna canónica nueva es un cambio de contrato: va en 04_Migraciones. */
IF OBJECT_ID('ops.Issue', 'U') IS NULL
CREATE TABLE ops.Issue (
    IssueSk                 bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ops_Issue PRIMARY KEY,
    FuenteId                int            NOT NULL,
    IssueId                 varchar(30)    NOT NULL,   -- id de Jira (estable aunque el issue cambie de proyecto)
    Clave                   varchar(50)    NOT NULL,   -- SMC26-18 (puede cambiar al mover el issue)
    ProyectoId              varchar(30)    NULL,
    TipoIssueId             varchar(30)    NULL,
    TipoIssue               nvarchar(255)  NULL,
    EstadoId                varchar(30)    NULL,
    CategoriaEstado         varchar(20)    NULL,
    PrioridadId             varchar(30)    NULL,
    Prioridad               nvarchar(100)  NULL,
    ResolucionId            varchar(30)    NULL,
    Resolucion              nvarchar(100)  NULL,
    ResponsableId           varchar(128)   NULL,
    InformanteId            varchar(128)   NULL,
    Resumen                 nvarchar(1000) NULL,
    PadreClave              varchar(50)    NULL,
    EsSubtarea              bit            NOT NULL CONSTRAINT DF_ops_Issue_EsSubtarea DEFAULT 0,   -- issuetype.subtask: sus horas se suman en el padre
    TipoSolicitudId         varchar(30)    NULL,       -- JSM: request type
    TipoSolicitud           nvarchar(255)  NULL,
    StoryPoints             decimal(9,2)   NULL,
    TiempoInvertidoSeg      bigint         NULL,
    EstimacionOriginalSeg   bigint         NULL,
    EstimacionRestanteSeg   bigint         NULL,
    Creado                  datetimeoffset(3) NULL,
    Actualizado             datetimeoffset(3) NULL,
    Resuelto                datetimeoffset(3) NULL,
    Vencimiento             date           NULL,
    Eliminado               bit            NOT NULL CONSTRAINT DF_ops_Issue_Eliminado DEFAULT 0,
    DocumentoId             bigint         NULL,       -- raw.Documento de donde salió
    Integrado               datetimeoffset(3) NOT NULL CONSTRAINT DF_ops_Issue_Integrado DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT UQ_ops_Issue UNIQUE (FuenteId, IssueId)
);
GO
