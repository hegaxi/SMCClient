/* Lista para elegir una épica (campos "Épica" de las consultas). Valor = clave; detalle = resumen y estado. Con
   @Proyecto solo las de ese proyecto. Primero las abiertas. */
CREATE OR ALTER PROCEDURE api.Epicas_Listar
    @Proyecto varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.Clave AS Valor, i.Clave AS Etiqueta, CONCAT(LEFT(i.Resumen, 120), N' · ', i.Estado) AS Detalle
    FROM rpt.vIssue i
    WHERE i.NivelJerarquia >= 1 AND (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto)
    ORDER BY i.Abierto DESC, i.Creado DESC;
END;
GO
