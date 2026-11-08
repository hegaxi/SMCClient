/* Una fila por instancia de Jira. Permite tener más de un sitio (escala horizontal por fuente). */
IF OBJECT_ID('cfg.Fuente', 'U') IS NULL
CREATE TABLE cfg.Fuente (
    FuenteId          int IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_Fuente PRIMARY KEY,
    Codigo            varchar(50)    NOT NULL CONSTRAINT UQ_cfg_Fuente_Codigo UNIQUE,  -- 'smco'
    Tipo              varchar(30)    NOT NULL,          -- 'jira-cloud' | 'jira-dc'
    UrlBase           nvarchar(300)  NOT NULL,          -- https://smco.atlassian.net
    CloudId           varchar(64)    NULL,
    Activa            bit            NOT NULL CONSTRAINT DF_cfg_Fuente_Activa DEFAULT 1,
    MaxAntiguedadMin  int            NOT NULL CONSTRAINT DF_cfg_Fuente_MaxAntiguedad DEFAULT 30, -- datos "viejos" después de esto
    FechaAlta         datetimeoffset(3) NOT NULL CONSTRAINT DF_cfg_Fuente_FechaAlta DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT CK_cfg_Fuente_Tipo CHECK (Tipo IN ('jira-cloud', 'jira-dc'))
);
GO
