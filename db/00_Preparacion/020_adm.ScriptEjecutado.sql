/* Bitácora de despliegue: qué script corrió, con qué contenido (hash) y cuándo.
   Los scripts de 04_Migraciones se ejecutan una sola vez gracias a esta tabla. */
IF SCHEMA_ID('adm') IS NULL EXEC ('CREATE SCHEMA adm AUTHORIZATION dbo;');
GO
IF OBJECT_ID('adm.ScriptEjecutado', 'U') IS NULL
CREATE TABLE adm.ScriptEjecutado (
    Ruta        nvarchar(400)  NOT NULL CONSTRAINT PK_adm_ScriptEjecutado PRIMARY KEY,
    Hash        char(64)       NOT NULL,
    Ejecuciones int            NOT NULL CONSTRAINT DF_adm_ScriptEjecutado_Ejecuciones DEFAULT 1,
    Primera     datetimeoffset(3) NOT NULL CONSTRAINT DF_adm_ScriptEjecutado_Primera DEFAULT SYSDATETIMEOFFSET(),
    Ultima      datetimeoffset(3) NOT NULL CONSTRAINT DF_adm_ScriptEjecutado_Ultima DEFAULT SYSDATETIMEOFFSET()
);
GO
