/* Lista de IDs externos (conciliación de borrados). */
IF TYPE_ID('sync.IdTipo') IS NULL
CREATE TYPE sync.IdTipo AS TABLE (
    IdExterno varchar(100) NOT NULL PRIMARY KEY
);
GO
