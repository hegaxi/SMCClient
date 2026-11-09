/* Parámetros generales (clave/valor). Se cambian con UPDATE, sin desplegar código. */
IF OBJECT_ID('cfg.Parametro', 'U') IS NULL
CREATE TABLE cfg.Parametro (
    Clave       varchar(100)   NOT NULL CONSTRAINT PK_cfg_Parametro PRIMARY KEY,
    Valor       nvarchar(4000) NOT NULL,
    Descripcion nvarchar(400)  NULL
);
GO
