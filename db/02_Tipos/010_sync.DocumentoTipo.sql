/* Lote de documentos JSON que el worker envía en una sola llamada (TVP). */
IF TYPE_ID('sync.DocumentoTipo') IS NULL
CREATE TYPE sync.DocumentoTipo AS TABLE (
    IdExterno   varchar(100)      NOT NULL PRIMARY KEY,
    Actualizado datetimeoffset(3) NULL,      -- fecha de modificación en Jira (para la marca de agua)
    Json        nvarchar(max)     NOT NULL
);
GO
