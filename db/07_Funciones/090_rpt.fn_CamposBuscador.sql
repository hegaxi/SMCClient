/* Todos los campos del buscador: los estándar (cfg.CampoConsulta) y los personalizados de Jira (meta.CampoJira,
   activos y que se guardan), con su tipo, su expresión de valores múltiples y los operadores que admite.
   Los personalizados usan la clave "cf:<id de Jira>" y sus valores salen de ops.IssueCampoValor; si Jira agrega un
   campo, aparece aquí en cuanto la sincronización de metadatos lo registra, sin cambiar código. */
CREATE OR ALTER FUNCTION rpt.fn_CamposBuscador ()
RETURNS TABLE
AS
RETURN
    WITH c AS (
        SELECT Clave, Etiqueta, Tipo, Expresion, ExpresionMulti, Alias, EsColumna, ColumnaPredeterminada, Orden, CAST(N'Jira' AS nvarchar(20)) AS Origen
        FROM cfg.CampoConsulta
        UNION ALL
        SELECT CAST(N'cf:' + p.CampoId AS varchar(60)),
               p.Nombre,
               p.Tipo,
               CAST(NULL AS nvarchar(600)),
               CAST(N'SELECT x.' + CASE p.Tipo WHEN 'numero' THEN N'ValorNumero' WHEN 'fecha' THEN N'ValorFecha' ELSE N'ValorTexto' END
                    + N' FROM ops.IssueCampoValor x WHERE x.IssueSk = i.IssueSk AND x.CampoId = N''' + REPLACE(p.CampoId, N'''', N'''''') + N'''' AS nvarchar(600)),
               CAST(LEFT(p.Nombre, 100) AS nvarchar(100)), CAST(1 AS bit), CAST(0 AS bit), 1000, CAST(N'Personalizado' AS nvarchar(20))
        FROM (
            SELECT m.CampoId, MAX(m.Nombre) AS Nombre,
                   CASE WHEN MAX(m.TipoSchema) = 'number' THEN 'numero'
                        WHEN MAX(m.TipoSchema) IN ('date', 'datetime') THEN 'fecha'
                        WHEN MAX(m.TipoSchema) IN ('option', 'user', 'version', 'component', 'priority', 'sd-customerrequesttype', 'option-with-child')
                          OR MAX(m.ItemsSchema) IN ('option', 'user', 'string', 'version', 'component', 'json', 'group', 'sd-customerorganization') THEN 'lista'
                        ELSE 'texto' END AS Tipo
            FROM meta.CampoJira m
            WHERE m.EsCustom = 1 AND m.Activo = 1 AND m.GuardarValor = 1 AND m.CampoId LIKE 'customfield[_]%'
              -- Los que ya alimentan un campo estándar (sprint, story points, tipo de solicitud…) no se repiten.
              AND NOT EXISTS (SELECT 1 FROM cfg.MapeoCampo r WHERE r.CampoId = m.CampoId)
            GROUP BY m.CampoId
        ) p
    )
    SELECT c.*,
           CASE c.Tipo
               WHEN 'texto'   THEN 'contiene,no_contiene,igual,distinto,vacio,no_vacio'
               WHEN 'numero'  THEN 'igual,distinto,mayor,mayor_igual,menor,menor_igual,entre,vacio,no_vacio'
               WHEN 'fecha'   THEN 'desde,hasta,entre,igual,vacio,no_vacio'
               WHEN 'bit'     THEN 'es'
               ELSE                'en,no_en,vacio,no_vacio' END AS Operadores
    FROM c;
GO
