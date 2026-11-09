/* Lista para elegir una persona de Jira (responsable, quien registró tiempo). Solo cuentas de personas que aparecen
   en los datos (responsables de issues o autores de worklogs); con @Proyecto, las de ese proyecto. Valor = accountId
   (para los filtros por id) y Nombre (para los filtros por nombre). @Proyecto: una clave o varias separadas por '|'. */
CREATE OR ALTER PROCEDURE api.Personas_Listar
    @Proyecto varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.AccountId, u.Nombre, CONCAT(COUNT(DISTINCT x.IssueSk), N' issues') AS Detalle
    FROM ops.Usuario u
    JOIN (SELECT i.FuenteId, i.ResponsableId AS AccountId, i.IssueSk FROM rpt.vIssue i
          WHERE i.ResponsableId IS NOT NULL AND (@Proyecto IS NULL OR i.ProyectoClave IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Proyecto, '|')))
          UNION ALL
          SELECT w.FuenteId, w.AutorId, w.IssueSk FROM rpt.vWorklog w
          WHERE w.Origen = 'manual' AND (@Proyecto IS NULL OR w.ProyectoClave IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Proyecto, '|')))) x
      ON x.FuenteId = u.FuenteId AND x.AccountId = u.AccountId
    WHERE ISNULL(u.TipoCuenta, 'atlassian') = 'atlassian'
    GROUP BY u.AccountId, u.Nombre
    ORDER BY u.Nombre;
END;
GO
