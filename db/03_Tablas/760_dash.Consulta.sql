/* Consultas personalizadas: una búsqueda avanzada (criterios, columnas y orden de api.Issues_Consultar) con nombre, que un
   administrador publica y comparte con usuarios o roles (dash.ConsultaAcceso), incluidos clientes externos. */
IF OBJECT_ID('dash.Consulta', 'U') IS NULL
CREATE TABLE dash.Consulta (
    ConsultaId     int IDENTITY(1,1) NOT NULL CONSTRAINT PK_dash_Consulta PRIMARY KEY,
    Nombre         nvarchar(150)  NOT NULL CONSTRAINT UQ_dash_Consulta_Nombre UNIQUE,
    Descripcion    nvarchar(500)  NULL,
    Criterios      nvarchar(max)  NOT NULL CONSTRAINT DF_dash_Consulta_Criterios DEFAULT N'[]',
    Columnas       nvarchar(2000) NULL,
    OrdenarPor     varchar(60)    NULL,
    Descendente    bit            NOT NULL CONSTRAINT DF_dash_Consulta_Descendente DEFAULT 1,
    PropietarioId  int            NOT NULL,
    FechaAlta      datetimeoffset(3) NOT NULL CONSTRAINT DF_dash_Consulta_FechaAlta DEFAULT SYSDATETIMEOFFSET(),
    FechaCambio    datetimeoffset(3) NOT NULL CONSTRAINT DF_dash_Consulta_FechaCambio DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT CK_dash_Consulta_Criterios CHECK (ISJSON(Criterios) = 1)
);
GO
