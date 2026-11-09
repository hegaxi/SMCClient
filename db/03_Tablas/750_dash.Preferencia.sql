/* Preferencias por usuario: el tablero que ve al entrar. */
IF OBJECT_ID('dash.Preferencia', 'U') IS NULL
CREATE TABLE dash.Preferencia (
    UsuarioId        int NOT NULL CONSTRAINT PK_dash_Preferencia PRIMARY KEY,
    TableroInicioId  int NULL
);
GO
