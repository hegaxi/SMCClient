/* Catálogo de campos descubierto en GET /rest/api/3/field. El ID es estable; el nombre puede cambiar. */
IF OBJECT_ID('meta.CampoJira', 'U') IS NULL
CREATE TABLE meta.CampoJira (
    FuenteId        int            NOT NULL,
    CampoId         varchar(100)   NOT NULL,  -- 'customfield_10020' | 'status'
    Nombre          nvarchar(255)  NOT NULL,
    EsCustom        bit            NOT NULL,
    TipoSchema      varchar(100)   NULL,      -- number, option, user, array, sd-servicelevelagreement...
    ItemsSchema     varchar(100)   NULL,      -- tipo de los elementos cuando es arreglo
    TipoCustom      nvarchar(200)  NULL,      -- com.atlassian.servicedesk:sd-sla-field
    CampoSistema    varchar(100)   NULL,
    GuardarValor    bit            NOT NULL CONSTRAINT DF_meta_CampoJira_Guardar DEFAULT 1, -- copiar a ops.IssueCampoValor
    Activo          bit            NOT NULL CONSTRAINT DF_meta_CampoJira_Activo DEFAULT 1,
    PrimeraVez      datetimeoffset(3) NOT NULL,
    UltimaVez       datetimeoffset(3) NOT NULL,
    FechaBaja       datetimeoffset(3) NULL,
    HashDefinicion  binary(32)     NULL,      -- para detectar cambios de nombre o tipo
    CONSTRAINT PK_meta_CampoJira PRIMARY KEY (FuenteId, CampoId)
);
GO
