/* Filtro guardado: una consulta (procedimiento del esquema api) con valores para sus parámetros.
   Parametros es JSON {"TipoProyecto":"service_desk","Desde":"{inicio_mes}"}; los valores entre llaves son
   fechas relativas que se resuelven al usarse (ver dash.fn_FechaRelativa). */
IF OBJECT_ID('dash.Filtro', 'U') IS NULL
CREATE TABLE dash.Filtro (
    FiltroId       int IDENTITY(1,1) NOT NULL CONSTRAINT PK_dash_Filtro PRIMARY KEY,
    Nombre         nvarchar(150)  NOT NULL,
    Procedimiento  sysname        NOT NULL,           -- nombre en el esquema api, sin el esquema
    Parametros     nvarchar(max)  NOT NULL CONSTRAINT DF_dash_Filtro_Parametros DEFAULT N'{}',
    PropietarioId  int            NOT NULL,
    Compartido     bit            NOT NULL CONSTRAINT DF_dash_Filtro_Compartido DEFAULT 0,   -- visible para quien pueda ejecutar la consulta
    FechaAlta      datetimeoffset(3) NOT NULL CONSTRAINT DF_dash_Filtro_FechaAlta DEFAULT SYSDATETIMEOFFSET(),
    FechaCambio    datetimeoffset(3) NOT NULL CONSTRAINT DF_dash_Filtro_FechaCambio DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT UQ_dash_Filtro UNIQUE (PropietarioId, Nombre),
    CONSTRAINT CK_dash_Filtro_Parametros CHECK (ISJSON(Parametros) = 1)
);
GO
