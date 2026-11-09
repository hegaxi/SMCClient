/* Quién puede ver una consulta personalizada: Tipo 'U' = usuario (Id = UsuarioId), 'R' = rol (Id = RolId).
   Los administradores ven todas. */
IF OBJECT_ID('dash.ConsultaAcceso', 'U') IS NULL
CREATE TABLE dash.ConsultaAcceso (
    ConsultaId  int     NOT NULL,
    Tipo        char(1) NOT NULL,
    Id          int     NOT NULL,
    CONSTRAINT PK_dash_ConsultaAcceso PRIMARY KEY (ConsultaId, Tipo, Id),
    CONSTRAINT CK_dash_ConsultaAcceso_Tipo CHECK (Tipo IN ('U', 'R'))
);
GO
