/* Comentarios de los issues (GET /rest/api/2/issue/{id}/comment: el cuerpo llega como texto). En mesa de ayuda,
   Publico = 1 si lo ve el cliente (jsdPublic) y 0 si es una nota interna; NULL en proyectos que no son de JSM. */
IF OBJECT_ID('ops.Comentario', 'U') IS NULL
CREATE TABLE ops.Comentario (
    FuenteId      int            NOT NULL,
    ComentarioId  varchar(30)    NOT NULL,
    IssueId       varchar(30)    NOT NULL,
    AutorId       varchar(128)   NULL,
    Cuerpo        nvarchar(max)  NULL,
    Publico       bit            NULL,
    Creado        datetimeoffset(3) NULL,
    Actualizado   datetimeoffset(3) NULL,
    Eliminado     bit            NOT NULL CONSTRAINT DF_ops_Comentario_Eliminado DEFAULT 0,
    CONSTRAINT PK_ops_Comentario PRIMARY KEY (FuenteId, ComentarioId)
);
GO
