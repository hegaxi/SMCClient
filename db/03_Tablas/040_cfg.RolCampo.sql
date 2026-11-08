/* Roles lógicos que necesita el modelo canónico (estado, responsable, story points, sprint...).
   NO apuntan a un ID de Jira: tienen REGLAS para encontrar el campo (sistema, tipo custom o nombre).
   Si Jira recrea un campo con otro ID, la regla lo vuelve a encontrar. */
IF OBJECT_ID('cfg.RolCampo', 'U') IS NULL
CREATE TABLE cfg.RolCampo (
    Rol                varchar(50)   NOT NULL CONSTRAINT PK_cfg_RolCampo PRIMARY KEY,
    Descripcion        nvarchar(300) NOT NULL,
    TipoDato           varchar(10)   NOT NULL,   -- texto | numero | fecha | id
    Obligatorio        bit           NOT NULL CONSTRAINT DF_cfg_RolCampo_Obligatorio DEFAULT 0,
    ReglaCampoSistema  varchar(100)  NULL,       -- 'status', 'assignee'... (campos del sistema)
    ReglaTipoCustom    nvarchar(200) NULL,       -- 'com.pyxis.greenhopper.jira:gh-sprint'
    ReglaNombre        nvarchar(400) NULL,       -- nombres aceptados separados por '|', sin distinguir mayúsculas
    RutaValor          nvarchar(200) NOT NULL CONSTRAINT DF_cfg_RolCampo_RutaValor DEFAULT N'$',  -- dentro del valor del campo
    RutaTexto          nvarchar(200) NULL,       -- texto legible (nombre del estado, displayName...)
    CONSTRAINT CK_cfg_RolCampo_TipoDato CHECK (TipoDato IN ('texto', 'numero', 'fecha', 'id')),
    CONSTRAINT CK_cfg_RolCampo_Regla CHECK (ReglaCampoSistema IS NOT NULL OR ReglaTipoCustom IS NOT NULL OR ReglaNombre IS NOT NULL)
);
GO
