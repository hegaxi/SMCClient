/* Qué se sincroniza de cada fuente, cada cuánto, con qué endpoint y qué procedimiento lo integra.
   Si Atlassian cambia un endpoint o su versión, se actualiza aquí (el worker lo lee). */
IF OBJECT_ID('cfg.EntidadSync', 'U') IS NULL
CREATE TABLE cfg.EntidadSync (
    FuenteId       int            NOT NULL,
    Entidad        varchar(40)    NOT NULL,   -- campo | proyecto | estado | issue | changelog | worklog | worklog_eliminado | sla
    Activa         bit            NOT NULL CONSTRAINT DF_cfg_EntidadSync_Activa DEFAULT 1,
    Orden          int            NOT NULL,   -- orden de integración (campo antes que issue, issue antes que worklog...)
    Modo           varchar(20)    NOT NULL,   -- 'catalogo' (foto completa) | 'incremental' | 'dependiente' (se pide por issue)
    FrecuenciaMin  int            NOT NULL CONSTRAINT DF_cfg_EntidadSync_Frecuencia DEFAULT 15,
    Endpoint       nvarchar(300)  NOT NULL,
    TamanoLote     int            NOT NULL CONSTRAINT DF_cfg_EntidadSync_TamanoLote DEFAULT 100,
    Procedimiento  sysname        NOT NULL,   -- sync.Procesar_* que integra los documentos
    ProcedimientoCierre sysname   NULL,       -- sync.Cerrar_* al terminar un catálogo completo (bajas)
    Parametros     nvarchar(max)  NULL,       -- JSON libre para el worker (p. ej. JQL base)
    CONSTRAINT PK_cfg_EntidadSync PRIMARY KEY (FuenteId, Entidad),
    CONSTRAINT CK_cfg_EntidadSync_Modo CHECK (Modo IN ('catalogo', 'incremental', 'dependiente')),
    CONSTRAINT CK_cfg_EntidadSync_Parametros CHECK (Parametros IS NULL OR ISJSON(Parametros) = 1)
);
GO
