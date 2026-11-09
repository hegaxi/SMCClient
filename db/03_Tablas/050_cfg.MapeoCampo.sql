/* Resultado de aplicar las reglas de cfg.RolCampo a cada fuente: rol -> campo real.
   Origen 'manual' tiene prioridad y nunca se sobrescribe; 'auto' se recalcula en cada sincronización. */
IF OBJECT_ID('cfg.MapeoCampo', 'U') IS NULL
CREATE TABLE cfg.MapeoCampo (
    FuenteId        int            NOT NULL,
    Rol             varchar(50)    NOT NULL,
    CampoId         varchar(100)   NULL,      -- NULL = no se encontró campo para el rol
    Origen          varchar(10)    NOT NULL,  -- auto | manual
    FechaResolucion datetimeoffset(3) NOT NULL CONSTRAINT DF_cfg_MapeoCampo_Fecha DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_cfg_MapeoCampo PRIMARY KEY (FuenteId, Rol),
    CONSTRAINT CK_cfg_MapeoCampo_Origen CHECK (Origen IN ('auto', 'manual'))
);
GO
