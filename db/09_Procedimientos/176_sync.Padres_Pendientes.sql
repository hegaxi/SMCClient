/* Padres y épicas que faltan: claves que los issues mencionan en PadreClave y que no están en ops.Issue (por ejemplo,
   épicas sin cambios desde antes de la carga inicial, o padres en otro proyecto). Los encola, quita los que ya llegaron
   y entrega hasta @Max claves para que el worker los traiga por clave (/rest/api/3/issue/bulkfetch).
   No se piden los de proyectos excluidos. Uno que Jira ya no tiene se reintenta una vez al día tras 5 intentos. */
CREATE OR ALTER PROCEDURE sync.Padres_Pendientes
    @Fuente varchar(50),
    @Max    int = 500
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50404, 'La fuente no existe.', 1;

    MERGE sync.IssuePendiente AS t
    USING (
        SELECT DISTINCT i.PadreClave
        FROM ops.Issue i
        WHERE i.FuenteId = @FuenteId AND i.Eliminado = 0 AND i.PadreClave IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM ops.Issue p WHERE p.FuenteId = @FuenteId AND p.Clave = i.PadreClave)
          AND NOT EXISTS (SELECT 1 FROM cfg.ProyectoExcluido x
                          WHERE x.FuenteId = @FuenteId AND x.ProyectoClave = LEFT(i.PadreClave, CHARINDEX('-', i.PadreClave + '-') - 1))
    ) AS s ON t.FuenteId = @FuenteId AND t.Entidad = 'padre' AND t.IssueId = s.PadreClave
    WHEN NOT MATCHED THEN INSERT (FuenteId, Entidad, IssueId, Clave) VALUES (@FuenteId, 'padre', s.PadreClave, s.PadreClave);

    DELETE t FROM sync.IssuePendiente t
    WHERE t.FuenteId = @FuenteId AND t.Entidad = 'padre'
      AND (EXISTS (SELECT 1 FROM ops.Issue p WHERE p.FuenteId = @FuenteId AND p.Clave = t.IssueId)
           OR NOT EXISTS (SELECT 1 FROM ops.Issue h WHERE h.FuenteId = @FuenteId AND h.PadreClave = t.IssueId AND h.Eliminado = 0));

    EXEC sync.IssuePendiente_Tomar @Fuente = @Fuente, @Entidad = 'padre', @Max = @Max;
END;
GO
