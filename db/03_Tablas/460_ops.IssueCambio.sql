/* Historial (changelog) de cualquier campo: estado, responsable, prioridad, campos nuevos...
   Sirve para lead time, cycle time y tiempo en cada estado. */
IF OBJECT_ID('ops.IssueCambio', 'U') IS NULL
CREATE TABLE ops.IssueCambio (
    FuenteId     int            NOT NULL,
    HistoriaId   varchar(30)    NOT NULL,
    Orden        smallint       NOT NULL,
    IssueSk      bigint         NOT NULL,
    Fecha        datetimeoffset(3) NOT NULL,
    AutorId      varchar(128)   NULL,
    CampoId      varchar(100)   NULL,          -- fieldId (estable)
    Campo        nvarchar(255)  NULL,          -- field (nombre visible al momento del cambio)
    Desde        nvarchar(400)  NULL,
    DesdeTexto   nvarchar(1000) NULL,
    Hacia        nvarchar(400)  NULL,
    HaciaTexto   nvarchar(1000) NULL,
    CONSTRAINT PK_ops_IssueCambio PRIMARY KEY (FuenteId, HistoriaId, Orden)
);
GO
