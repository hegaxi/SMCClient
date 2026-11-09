/* Cada corrida del worker por fuente/entidad. Su Id es el "lote" de raw.Documento. */
IF OBJECT_ID('sync.Ejecucion', 'U') IS NULL
CREATE TABLE sync.Ejecucion (
    EjecucionId  bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sync_Ejecucion PRIMARY KEY,
    FuenteId     int            NOT NULL,
    Entidad      varchar(40)    NOT NULL,
    Modo         varchar(20)    NOT NULL,      -- inicial | incremental | catalogo | backfill | conciliacion | reproceso
    Inicio       datetimeoffset(3) NOT NULL CONSTRAINT DF_sync_Ejecucion_Inicio DEFAULT SYSDATETIMEOFFSET(),
    Fin          datetimeoffset(3) NULL,
    Estado       varchar(15)    NOT NULL CONSTRAINT DF_sync_Ejecucion_Estado DEFAULT 'corriendo',
    Leidos       int            NOT NULL CONSTRAINT DF_sync_Ejecucion_Leidos DEFAULT 0,
    Cambiados    int            NOT NULL CONSTRAINT DF_sync_Ejecucion_Cambiados DEFAULT 0,
    Procesados   int            NOT NULL CONSTRAINT DF_sync_Ejecucion_Procesados DEFAULT 0,
    Errores      int            NOT NULL CONSTRAINT DF_sync_Ejecucion_Errores DEFAULT 0,
    Servidor     nvarchar(128)  NULL,
    Mensaje      nvarchar(2000) NULL,
    CONSTRAINT CK_sync_Ejecucion_Estado CHECK (Estado IN ('corriendo', 'ok', 'parcial', 'error'))
);
GO
