/* Arrendamiento (lease) por fuente: evita que dos workers sincronicen la misma fuente a la vez,
   aunque corran en servidores distintos. Si un worker muere, el candado expira solo. */
IF OBJECT_ID('sync.Candado', 'U') IS NULL
CREATE TABLE sync.Candado (
    FuenteId     int            NOT NULL CONSTRAINT PK_sync_Candado PRIMARY KEY,
    Propietario  nvarchar(200)  NULL,
    ExpiraEn     datetimeoffset(3) NOT NULL
);
GO
