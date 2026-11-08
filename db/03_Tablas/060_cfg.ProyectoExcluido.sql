/* Proyectos que NO se sincronizan ni aparecen en reportes (pruebas, sandbox...).
   Por clave, porque es lo que el administrador conoce y lo que usa el JQL. */
IF OBJECT_ID('cfg.ProyectoExcluido', 'U') IS NULL
CREATE TABLE cfg.ProyectoExcluido (
    FuenteId       int            NOT NULL,
    ProyectoClave  varchar(50)    NOT NULL,
    Motivo         nvarchar(200)  NULL,
    Fecha          datetimeoffset(3) NOT NULL CONSTRAINT DF_cfg_ProyectoExcluido_Fecha DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_cfg_ProyectoExcluido PRIMARY KEY (FuenteId, ProyectoClave)
);
GO
