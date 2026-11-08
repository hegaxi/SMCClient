/* Hasta qué fecha de modificación se ha sincronizado cada entidad (sincronización incremental). */
IF OBJECT_ID('sync.MarcaAgua', 'U') IS NULL
CREATE TABLE sync.MarcaAgua (
    FuenteId       int            NOT NULL,
    Entidad        varchar(40)    NOT NULL,
    Valor          datetimeoffset(3) NULL,
    EjecucionId    bigint         NULL,
    ActualizadoEn  datetimeoffset(3) NOT NULL CONSTRAINT DF_sync_MarcaAgua_Fecha DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_sync_MarcaAgua PRIMARY KEY (FuenteId, Entidad)
);
GO
