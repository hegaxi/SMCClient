IF OBJECT_ID('dash.Tablero', 'U') IS NULL
CREATE TABLE dash.Tablero (
    TableroId      int IDENTITY(1,1) NOT NULL CONSTRAINT PK_dash_Tablero PRIMARY KEY,
    Nombre         nvarchar(150)  NOT NULL,
    Descripcion    nvarchar(400)  NULL,
    PropietarioId  int            NOT NULL,
    FechaAlta      datetimeoffset(3) NOT NULL CONSTRAINT DF_dash_Tablero_FechaAlta DEFAULT SYSDATETIMEOFFSET(),
    FechaCambio    datetimeoffset(3) NOT NULL CONSTRAINT DF_dash_Tablero_FechaCambio DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT UQ_dash_Tablero UNIQUE (PropietarioId, Nombre)
);
GO
