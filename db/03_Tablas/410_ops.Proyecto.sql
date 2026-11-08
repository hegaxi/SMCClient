IF OBJECT_ID('ops.Proyecto', 'U') IS NULL
CREATE TABLE ops.Proyecto (
    FuenteId      int            NOT NULL,
    ProyectoId    varchar(30)    NOT NULL,     -- id de Jira ('10658')
    Clave         varchar(50)    NOT NULL,     -- 'SMC26'
    Nombre        nvarchar(255)  NULL,
    TipoProyecto  varchar(30)    NULL,         -- software (Scrum) | service_desk (mesa de ayuda) | business
    Estilo        varchar(20)    NULL,         -- classic | next-gen
    Eliminado     bit            NOT NULL CONSTRAINT DF_ops_Proyecto_Eliminado DEFAULT 0,
    Actualizado   datetimeoffset(3) NOT NULL CONSTRAINT DF_ops_Proyecto_Actualizado DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_ops_Proyecto PRIMARY KEY (FuenteId, ProyectoId)
);
GO
