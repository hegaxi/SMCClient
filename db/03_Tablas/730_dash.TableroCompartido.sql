/* Con quién se comparte un tablero: Tipo 'U' = usuario (Id = UsuarioId), 'R' = rol (Id = RolId). */
IF OBJECT_ID('dash.TableroCompartido', 'U') IS NULL
CREATE TABLE dash.TableroCompartido (
    TableroId  int     NOT NULL,
    Tipo       char(1) NOT NULL,
    Id         int     NOT NULL,
    CONSTRAINT PK_dash_TableroCompartido PRIMARY KEY (TableroId, Tipo, Id),
    CONSTRAINT CK_dash_TableroCompartido_Tipo CHECK (Tipo IN ('U', 'R'))
);
GO
