/* Padres y épicas que faltan: los que los issues mencionan (PadreId, o la clave si no hay id) y que no están en ops.Issue
   (por ejemplo, épicas sin cambios desde antes de la carga inicial, o padres en otro proyecto). Los encola, quita los
   que ya llegaron y entrega hasta @Max identificadores (id de Jira, o clave) para que el worker los traiga con
   /rest/api/3/issue/bulkfetch, que acepta ambos. No se piden los de proyectos excluidos (por el prefijo de la clave).
   Uno que Jira ya no tiene se reintenta una vez al día tras 5 intentos. */
CREATE OR ALTER PROCEDURE sync.Padres_Pendientes
    @Fuente varchar(50),
    @Max    int = 500
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50404, 'La fuente no existe.', 1;

    SELECT DISTINCT COALESCE(i.PadreId, i.PadreClave) AS Ref, MAX(i.PadreClave) OVER (PARTITION BY COALESCE(i.PadreId, i.PadreClave)) AS Clave
    INTO #faltan
    FROM ops.Issue i
    WHERE i.FuenteId = @FuenteId AND i.Eliminado = 0 AND (i.PadreId IS NOT NULL OR i.PadreClave IS NOT NULL)
      AND NOT EXISTS (SELECT 1 FROM ops.Issue p WHERE p.FuenteId = @FuenteId
                      AND (p.IssueId = i.PadreId OR (i.PadreId IS NULL AND p.Clave = i.PadreClave)))
      AND NOT EXISTS (SELECT 1 FROM cfg.ProyectoExcluido x
                      WHERE x.FuenteId = @FuenteId AND x.ProyectoClave = LEFT(i.PadreClave, CHARINDEX('-', i.PadreClave + '-') - 1));

    MERGE sync.IssuePendiente AS t
    USING #faltan AS s ON t.FuenteId = @FuenteId AND t.Entidad = 'padre' AND t.IssueId = s.Ref
    WHEN NOT MATCHED THEN INSERT (FuenteId, Entidad, IssueId, Clave) VALUES (@FuenteId, 'padre', s.Ref, s.Clave);

    -- Ya llegaron, o ningún issue los menciona.
    DELETE t FROM sync.IssuePendiente t
    WHERE t.FuenteId = @FuenteId AND t.Entidad = 'padre' AND NOT EXISTS (SELECT 1 FROM #faltan f WHERE f.Ref = t.IssueId);

    EXEC sync.IssuePendiente_Tomar @Fuente = @Fuente, @Entidad = 'padre', @Max = @Max;
END;
GO
