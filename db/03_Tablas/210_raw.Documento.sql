/* Última versión de cada documento JSON recibido de Jira, por fuente/entidad/id.
   Es la base para REPROCESAR: si cambia un mapeo, se recalcula ops desde aquí sin llamar a Jira. */
IF OBJECT_ID('raw.Documento', 'U') IS NULL
CREATE TABLE raw.Documento (
    DocumentoId   bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_raw_Documento PRIMARY KEY,
    FuenteId      int            NOT NULL,
    Entidad       varchar(40)    NOT NULL,
    IdExterno     varchar(100)   NOT NULL,
    Actualizado   datetimeoffset(3) NULL,
    Hash          binary(32)     NOT NULL,      -- SHA2_256 del JSON: si no cambió, no se reprocesa
    Json          nvarchar(max)  NOT NULL,
    LoteId        bigint         NOT NULL,      -- última ejecución que lo vio (sync.Ejecucion)
    Recibido      datetimeoffset(3) NOT NULL CONSTRAINT DF_raw_Documento_Recibido DEFAULT SYSDATETIMEOFFSET(),
    Procesado     bit            NOT NULL CONSTRAINT DF_raw_Documento_Procesado DEFAULT 0,
    ProcesadoEn   datetimeoffset(3) NULL,
    Intentos      tinyint        NOT NULL CONSTRAINT DF_raw_Documento_Intentos DEFAULT 0,
    ErrorProceso  nvarchar(2000) NULL,
    CONSTRAINT UQ_raw_Documento UNIQUE (FuenteId, Entidad, IdExterno),
    CONSTRAINT CK_raw_Documento_Json CHECK (ISJSON(Json) = 1)
);
GO
