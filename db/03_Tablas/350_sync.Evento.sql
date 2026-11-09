/* Avisos para el administrador: campo nuevo, campo eliminado, rol sin campo, documento con error... */
IF OBJECT_ID('sync.Evento', 'U') IS NULL
CREATE TABLE sync.Evento (
    EventoId     bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sync_Evento PRIMARY KEY,
    FuenteId     int            NULL,
    EjecucionId  bigint         NULL,
    Nivel        varchar(12)    NOT NULL,     -- info | advertencia | error
    Codigo       varchar(60)    NOT NULL,     -- campo.alta, campo.baja, rol.sin_campo, rol.ambiguo, documento.error...
    Mensaje      nvarchar(1000) NOT NULL,
    Datos        nvarchar(max)  NULL,
    Fecha        datetimeoffset(3) NOT NULL CONSTRAINT DF_sync_Evento_Fecha DEFAULT SYSDATETIMEOFFSET(),
    Atendido     bit            NOT NULL CONSTRAINT DF_sync_Evento_Atendido DEFAULT 0,
    CONSTRAINT CK_sync_Evento_Nivel CHECK (Nivel IN ('info', 'advertencia', 'error'))
);
GO
