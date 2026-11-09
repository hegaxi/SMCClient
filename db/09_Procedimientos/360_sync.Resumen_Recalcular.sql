/* Recalcula ops.IssueResumen:
   1) horas propias (registradas / automáticas) y último registro de los issues tocados (o de todos con @Todo = 1, y
      siempre de los que aún no tienen resumen);
   2) el árbol de TODA la fuente (barato: se suma sobre las horas propias, no sobre los worklogs): horas, estimación y
      último registro de cada issue con todos sus descendientes, y su épica (el antecesor más cercano de nivel épica).
      Estimación del árbol sin doble conteo: de cada rama cuenta la estimación de los elementos más detallados que la
      tienen (si una tarea y sus subtareas están estimadas, cuentan las subtareas; muchas veces la del padre es la suma
      copiada de las de sus hijos). Antes se sumaban ambas.
   La jerarquía se une por id de Jira (PadreId). */
CREATE OR ALTER PROCEDURE sync.Resumen_Recalcular
    @FuenteId int,
    @Issues   sync.IdTipo READONLY,
    @Todo     bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    /* 1. Horas propias */
    SELECT i.IssueSk, i.IssueId INTO #obj
    FROM ops.Issue i
    WHERE i.FuenteId = @FuenteId
      AND (@Todo = 1 OR i.IssueId IN (SELECT IdExterno FROM @Issues)
           OR NOT EXISTS (SELECT 1 FROM ops.IssueResumen r WHERE r.IssueSk = i.IssueSk));

    MERGE ops.IssueResumen AS t
    USING (
        SELECT o.IssueSk, o.IssueId,
               SUM(CASE WHEN w.EsAutomatico = 0 THEN CAST(w.Segundos AS bigint) END) AS Reg,
               SUM(CASE WHEN w.EsAutomatico = 1 AND ISNULL(w.EsCopia, 0) = 0 THEN CAST(w.Segundos AS bigint) END) AS Aut,
               SUM(CASE WHEN w.EsCopia = 1 THEN CAST(w.Segundos AS bigint) END) AS Copia,
               MAX(CASE WHEN ISNULL(w.EsCopia, 0) = 0 THEN w.Inicio END) AS Ultimo
        FROM #obj o
        LEFT JOIN ops.Worklog w ON w.FuenteId = @FuenteId AND w.IssueId = o.IssueId AND w.Eliminado = 0
        GROUP BY o.IssueSk, o.IssueId
    ) AS s ON t.IssueSk = s.IssueSk
    WHEN MATCHED THEN UPDATE SET SegRegPropios = s.Reg, SegAutPropios = s.Aut, SegCopiaPropios = s.Copia, UltimoRegistroPropio = s.Ultimo,
                                 Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (IssueSk, FuenteId, IssueId, SegRegPropios, SegAutPropios, SegCopiaPropios, UltimoRegistroPropio)
         VALUES (s.IssueSk, @FuenteId, s.IssueId, s.Reg, s.Aut, s.Copia, s.Ultimo);

    /* 2. Árbol de la fuente: (raíz, descendiente-o-ella-misma, distancia) */
    WITH arbol AS (
        SELECT i.IssueId AS Raiz, i.IssueId, 0 AS Nivel
        FROM ops.Issue i WHERE i.FuenteId = @FuenteId AND i.Eliminado = 0
        UNION ALL
        SELECT a.Raiz, h.IssueId, a.Nivel + 1
        FROM arbol a JOIN ops.Issue h ON h.FuenteId = @FuenteId AND h.PadreId = a.IssueId
        WHERE h.Eliminado = 0 AND a.Nivel < 5
    )
    SELECT Raiz, IssueId, Nivel INTO #arbol FROM arbol OPTION (MAXRECURSION 10);
    CREATE CLUSTERED INDEX ix ON #arbol (Raiz, Nivel);

    -- Estimación efectiva: la del issue si ninguno de sus descendientes está estimado.
    SELECT i.IssueId,
           CASE WHEN i.EstimacionOriginalSeg > 0
                     AND NOT EXISTS (SELECT 1 FROM #arbol d JOIN ops.Issue x ON x.FuenteId = @FuenteId AND x.IssueId = d.IssueId
                                     WHERE d.Raiz = i.IssueId AND d.Nivel > 0 AND x.EstimacionOriginalSeg > 0)
                THEN CAST(i.EstimacionOriginalSeg AS bigint) END AS EstEf
    INTO #est
    FROM ops.Issue i WHERE i.FuenteId = @FuenteId AND i.Eliminado = 0;
    CREATE UNIQUE CLUSTERED INDEX ix ON #est (IssueId);

    SELECT a.Raiz,
           SUM(r.SegRegPropios) AS Reg, SUM(r.SegAutPropios) AS Aut, SUM(r.SegCopiaPropios) AS Copia, MAX(r.UltimoRegistroPropio) AS Ultimo,
           SUM(e.EstEf) AS Est
    INTO #agg
    FROM #arbol a
    JOIN ops.Issue i ON i.FuenteId = @FuenteId AND i.IssueId = a.IssueId
    LEFT JOIN #est e ON e.IssueId = a.IssueId
    LEFT JOIN ops.IssueResumen r ON r.IssueSk = i.IssueSk
    GROUP BY a.Raiz;

    -- Épica: la raíz más cercana de nivel épica que contiene al issue (él mismo si es épica).
    SELECT IssueId, EpicaIssueId INTO #epica FROM (
        SELECT a.IssueId, a.Raiz AS EpicaIssueId, ROW_NUMBER() OVER (PARTITION BY a.IssueId ORDER BY a.Nivel) AS rn
        FROM #arbol a JOIN ops.Issue e ON e.FuenteId = @FuenteId AND e.IssueId = a.Raiz AND e.NivelJerarquia >= 1
    ) x WHERE rn = 1;

    UPDATE r SET SegRegArbol = g.Reg, SegAutArbol = g.Aut, SegCopiaArbol = g.Copia, EstimacionArbolSeg = g.Est, UltimoRegistroArbol = g.Ultimo,
                 EpicaIssueId = e.EpicaIssueId, Actualizado = SYSDATETIMEOFFSET()
    FROM ops.IssueResumen r
    LEFT JOIN #agg g ON g.Raiz = r.IssueId
    LEFT JOIN #epica e ON e.IssueId = r.IssueId
    WHERE r.FuenteId = @FuenteId
      AND EXISTS (SELECT r.SegRegArbol, r.SegAutArbol, r.SegCopiaArbol, r.EstimacionArbolSeg, r.UltimoRegistroArbol, r.EpicaIssueId
                  EXCEPT SELECT g.Reg, g.Aut, g.Copia, g.Est, g.Ultimo, e.EpicaIssueId);
END;
GO
