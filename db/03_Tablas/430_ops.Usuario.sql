/* Personas (agentes), clientes del portal (accountId 'qm:...') y apps (Automation for Jira).
   No se guarda el correo: es dato personal y no se necesita para los reportes. */
IF OBJECT_ID('ops.Usuario', 'U') IS NULL
CREATE TABLE ops.Usuario (
    FuenteId     int            NOT NULL,
    AccountId    varchar(128)   NOT NULL,
    Nombre       nvarchar(255)  NULL,
    TipoCuenta   varchar(20)    NULL,          -- atlassian | customer | app
    Activo       bit            NULL,
    Actualizado  datetimeoffset(3) NOT NULL CONSTRAINT DF_ops_Usuario_Actualizado DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_ops_Usuario PRIMARY KEY (FuenteId, AccountId)
);
GO
