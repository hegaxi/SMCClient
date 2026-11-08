/* Cola de trabajo: sincronizaciones pedidas por la interfaz o generadas por el sistema (backfill de un campo nuevo). */
IF OBJECT_ID('sync.Solicitud', 'U') IS NULL
CREATE TABLE sync.Solicitud (
    SolicitudId   bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sync_Solicitud PRIMARY KEY,
    FuenteId      int            NULL,         -- NULL = todas
    Entidad       varchar(40)    NULL,         -- NULL = todas
    Modo          varchar(20)    NOT NULL,     -- incremental | backfill | conciliacion | inicial
    Parametros    nvarchar(max)  NULL,         -- {"campoId":"customfield_10099"}
    SolicitadoPor nvarchar(200)  NOT NULL,
    Fecha         datetimeoffset(3) NOT NULL CONSTRAINT DF_sync_Solicitud_Fecha DEFAULT SYSDATETIMEOFFSET(),
    Estado        varchar(15)    NOT NULL CONSTRAINT DF_sync_Solicitud_Estado DEFAULT 'pendiente',
    TomadaEn      datetimeoffset(3) NULL,
    TerminadaEn   datetimeoffset(3) NULL,
    CONSTRAINT CK_sync_Solicitud_Estado CHECK (Estado IN ('pendiente', 'tomada', 'hecha', 'error')),
    CONSTRAINT CK_sync_Solicitud_Parametros CHECK (Parametros IS NULL OR ISJSON(Parametros) = 1)
);
GO
