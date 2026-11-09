/* Campos estándar del buscador de issues (además de todos los personalizados de meta.CampoJira).
   Es una LISTA BLANCA: el buscador solo arma SQL con estas expresiones; los valores siempre viajan como parámetros.
   Expresion: valor escalar sobre rpt.vIssue (alias i). ExpresionMulti: subconsulta que devuelve varios valores por issue
   (columna v), para campos como sprint o etiquetas. Tipo: texto | numero | fecha | lista | usuario | bit. */
IF OBJECT_ID('cfg.CampoConsulta', 'U') IS NULL
CREATE TABLE cfg.CampoConsulta (
    Clave                  varchar(60)    NOT NULL CONSTRAINT PK_cfg_CampoConsulta PRIMARY KEY,
    Etiqueta               nvarchar(100)  NOT NULL,
    Tipo                   varchar(10)    NOT NULL,
    Expresion              nvarchar(600)  NULL,
    ExpresionMulti         nvarchar(600)  NULL,
    Alias                  nvarchar(100)  NOT NULL,     -- nombre de la columna en el resultado
    EsColumna              bit            NOT NULL CONSTRAINT DF_cfg_CampoConsulta_EsColumna DEFAULT 1,
    ColumnaPredeterminada  bit            NOT NULL CONSTRAINT DF_cfg_CampoConsulta_Predet DEFAULT 0,
    Orden                  int            NOT NULL,
    CONSTRAINT CK_cfg_CampoConsulta_Tipo CHECK (Tipo IN ('texto', 'numero', 'fecha', 'lista', 'usuario', 'bit')),
    CONSTRAINT CK_cfg_CampoConsulta_Expr CHECK ((Expresion IS NULL AND ExpresionMulti IS NOT NULL) OR (Expresion IS NOT NULL AND ExpresionMulti IS NULL))
);
GO
