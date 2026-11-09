IF OBJECT_ID('seg.UsuarioRol', 'U') IS NULL
CREATE TABLE seg.UsuarioRol (
    UsuarioId  int NOT NULL,
    RolId      int NOT NULL,
    CONSTRAINT PK_seg_UsuarioRol PRIMARY KEY (UsuarioId, RolId)
);
GO
