/* Bitácora de acciones de administración: quién, qué, cuándo y el antes/después. */
IF OBJECT_ID('seg.Auditoria', 'U') IS NULL
CREATE TABLE seg.Auditoria (
    AuditoriaId  bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_seg_Auditoria PRIMARY KEY,
    Fecha        datetimeoffset(3) NOT NULL CONSTRAINT DF_seg_Auditoria_Fecha DEFAULT SYSDATETIMEOFFSET(),
    Usuario      nvarchar(200)  NOT NULL,
    Accion       varchar(60)    NOT NULL,     -- usuario.guardar, rol.eliminar, mapeo.establecer...
    Objeto       nvarchar(200)  NULL,
    Antes        nvarchar(max)  NULL,
    Despues      nvarchar(max)  NULL
);
GO
