IF OBJECT_ID('ops.Sprint', 'U') IS NULL
CREATE TABLE ops.Sprint (
    FuenteId     int            NOT NULL,
    SprintId     bigint         NOT NULL,
    Nombre       nvarchar(255)  NULL,
    Estado       varchar(20)    NULL,          -- future | active | closed
    TableroId    bigint         NULL,
    Objetivo     nvarchar(2000) NULL,
    Inicio       datetimeoffset(3) NULL,
    Fin          datetimeoffset(3) NULL,
    Completado   datetimeoffset(3) NULL,
    Actualizado  datetimeoffset(3) NOT NULL CONSTRAINT DF_ops_Sprint_Actualizado DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_ops_Sprint PRIMARY KEY (FuenteId, SprintId)
);
GO
