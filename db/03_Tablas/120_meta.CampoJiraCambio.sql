/* Bitácora de cambios en el catálogo de campos (altas, bajas, renombres, cambios de tipo). */
IF OBJECT_ID('meta.CampoJiraCambio', 'U') IS NULL
CREATE TABLE meta.CampoJiraCambio (
    CambioId       bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_meta_CampoJiraCambio PRIMARY KEY,
    FuenteId       int            NOT NULL,
    CampoId        varchar(100)   NOT NULL,
    TipoCambio     varchar(20)    NOT NULL,
    ValorAnterior  nvarchar(400)  NULL,
    ValorNuevo     nvarchar(400)  NULL,
    EjecucionId    bigint         NULL,
    Fecha          datetimeoffset(3) NOT NULL CONSTRAINT DF_meta_CampoJiraCambio_Fecha DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT CK_meta_CampoJiraCambio_Tipo CHECK (TipoCambio IN ('alta', 'baja', 'renombre', 'cambio_tipo', 'reactivado'))
);
GO
