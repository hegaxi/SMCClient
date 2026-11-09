/* Widget de un tablero: muestra el resultado de un filtro como indicador, tabla o barras.
   Configuracion (JSON) según el tipo:
     indicador {"columna":"Issues","agregacion":"suma|promedio|conteo|maximo|minimo|primero","resultado":0}
     barras    {"etiqueta":"Persona","valor":"HorasRegistradas","limite":10,"resultado":0}
     tabla     {"columnas":["Clave","Resumen"],"limite":10,"resultado":0}   */
IF OBJECT_ID('dash.Widget', 'U') IS NULL
CREATE TABLE dash.Widget (
    WidgetId       int IDENTITY(1,1) NOT NULL CONSTRAINT PK_dash_Widget PRIMARY KEY,
    TableroId      int            NOT NULL,
    Titulo         nvarchar(150)  NOT NULL,
    FiltroId       int            NOT NULL,
    Tipo           varchar(12)    NOT NULL,
    Configuracion  nvarchar(max)  NOT NULL CONSTRAINT DF_dash_Widget_Configuracion DEFAULT N'{}',
    Ancho          tinyint        NOT NULL CONSTRAINT DF_dash_Widget_Ancho DEFAULT 2,    -- columnas de 1 a 4
    Orden          int            NOT NULL,
    CONSTRAINT CK_dash_Widget_Tipo CHECK (Tipo IN ('indicador', 'tabla', 'barras')),
    CONSTRAINT CK_dash_Widget_Ancho CHECK (Ancho BETWEEN 1 AND 4),
    CONSTRAINT CK_dash_Widget_Configuracion CHECK (ISJSON(Configuracion) = 1)
);
GO
