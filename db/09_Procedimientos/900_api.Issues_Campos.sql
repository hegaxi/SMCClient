/* Campos disponibles en la búsqueda avanzada: estándar y personalizados de Jira, con su tipo y operadores. */
CREATE OR ALTER PROCEDURE api.Issues_Campos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Clave, Etiqueta, Tipo, Origen, CAST(CASE WHEN ExpresionMulti IS NOT NULL THEN 1 ELSE 0 END AS bit) AS Multivalor,
           EsColumna, ColumnaPredeterminada, Operadores, Alias
    FROM rpt.fn_CamposBuscador()
    ORDER BY CASE Origen WHEN N'Jira' THEN 0 ELSE 1 END, Orden, Etiqueta;
END;
GO
