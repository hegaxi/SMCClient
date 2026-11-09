/* Tiempo de un proyecto en jerarquía: proyecto → épicas → tareas → subtareas, con las horas de cada elemento y las de
   todo lo que tiene debajo (cada worklog se cuenta una sola vez). Las tareas sin épica van en "(Sin épica)".
   - Horas registradas por personas y automáticas (Automation for Jira) por separado; se pueden acotar a un periodo
     (fecha del worklog) y a una persona (a quien se atribuye el worklog, como en Horas por persona).
   - Estimación sin doble conteo: de cada rama cuenta la estimación original de los elementos más detallados que la
     tienen (si una tarea y sus subtareas están estimadas, cuentan las subtareas).
   - Una fila por elemento: Nodo / PadreNodo / Nivel arman el árbol en la interfaz (0 proyecto, 1 épica, 2 tarea, 3 subtarea). */
CREATE OR ALTER PROCEDURE api.Horas_Arbol
    @Proyecto     varchar(50),
    @Desde        date = NULL,
    @Hasta        date = NULL,
    @Persona      nvarchar(200) = NULL,
    @SoloConHoras bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM rpt.vIssue WHERE ProyectoClave = @Proyecto)
        THROW 50404, 'El proyecto no existe, no tiene issues o no se sincroniza.', 1;

    SELECT i.IssueSk, i.FuenteId, i.IssueId, i.Clave, i.PadreId, i.NivelJerarquia, i.TipoIssue, i.Resumen, i.Estado,
           i.Abierto, i.Responsable, i.EstimacionOriginalSeg, i.ProyectoNombre,
           RIGHT(REPLICATE('0', 9) + CAST(ISNULL(TRY_CAST(SUBSTRING(i.Clave, CHARINDEX('-', i.Clave) + 1, 20) AS int), 0) AS varchar(10)), 9) AS Num
    INTO #i
    FROM rpt.vIssue i
    WHERE i.ProyectoClave = @Proyecto;
    CREATE UNIQUE CLUSTERED INDEX IX ON #i (FuenteId, IssueId);

    -- Horas propias de cada issue en el periodo / persona.
    SELECT w.FuenteId, w.IssueId,
           SUM(CASE WHEN w.Origen = 'manual' THEN CAST(w.Segundos AS bigint) END) AS SegReg,
           SUM(CASE WHEN w.Origen = 'automatico' THEN CAST(w.Segundos AS bigint) END) AS SegAut,
           MAX(w.Inicio) AS Ultimo
    INTO #h
    FROM rpt.vWorklog w
    WHERE w.ProyectoClave = @Proyecto
      AND (@Desde IS NULL OR w.Fecha >= @Desde)
      AND (@Hasta IS NULL OR w.Fecha <= @Hasta)
      AND (@Persona IS NULL OR w.AtribuidoA LIKE N'%' + @Persona + N'%')
    GROUP BY w.FuenteId, w.IssueId;

    -- Árbol: raíces = issues cuyo padre no está en el proyecto. Las épicas cuelgan del proyecto; lo demás, de "(Sin épica)".
    WITH arbol AS (
        SELECT r.FuenteId, r.IssueId, r.Clave,
               CAST(CASE WHEN r.NivelJerarquia >= 1 THEN N'#proyecto' ELSE N'#sin-epica' END AS nvarchar(60)) AS PadreNodo,
               CAST(CASE WHEN r.NivelJerarquia >= 1 THEN 1 ELSE 2 END AS int) AS Nivel,
               CAST(CASE WHEN r.NivelJerarquia >= 1 THEN '1/' ELSE '2/' END + r.Num AS varchar(400)) AS Ruta
        FROM #i r
        WHERE r.PadreId IS NULL OR NOT EXISTS (SELECT 1 FROM #i p WHERE p.FuenteId = r.FuenteId AND p.IssueId = r.PadreId)
        UNION ALL
        SELECT h.FuenteId, h.IssueId, h.Clave, CAST(a.Clave AS nvarchar(60)), a.Nivel + 1, CAST(a.Ruta + '/' + h.Num AS varchar(400))
        FROM arbol a JOIN #i h ON h.FuenteId = a.FuenteId AND h.PadreId = a.IssueId
        WHERE a.Nivel < 6
    )
    SELECT FuenteId, IssueId, Clave, PadreNodo, Nivel, Ruta INTO #n FROM arbol OPTION (MAXRECURSION 10);

    -- Pares (ancestro, descendiente o él mismo) para sumar cada rama.
    WITH par AS (
        SELECT n.FuenteId, n.IssueId AS Anc, n.IssueId AS Des, 0 AS D FROM #n n
        UNION ALL
        SELECT p.FuenteId, p.Anc, h.IssueId, p.D + 1
        FROM par p JOIN #i h ON h.FuenteId = p.FuenteId AND h.PadreId = p.Des
        WHERE p.D < 6
    )
    SELECT FuenteId, Anc, Des, D INTO #par FROM par OPTION (MAXRECURSION 10);

    -- Estimación efectiva: la del elemento si nada debajo de él está estimado.
    SELECT i.FuenteId, i.IssueId,
           CASE WHEN i.EstimacionOriginalSeg > 0
                     AND NOT EXISTS (SELECT 1 FROM #par x JOIN #i d ON d.FuenteId = x.FuenteId AND d.IssueId = x.Des
                                     WHERE x.FuenteId = i.FuenteId AND x.Anc = i.IssueId AND x.D > 0 AND d.EstimacionOriginalSeg > 0)
                THEN CAST(i.EstimacionOriginalSeg AS bigint) END AS EstEf
    INTO #e
    FROM #i i;

    SELECT p.FuenteId, p.Anc AS IssueId,
           SUM(h.SegReg) AS SegReg, SUM(h.SegAut) AS SegAut, SUM(e.EstEf) AS Est, MAX(h.Ultimo) AS Ultimo,
           COUNT(*) AS Elementos, SUM(CASE WHEN d.Abierto = 1 THEN 1 ELSE 0 END) AS Abiertos
    INTO #t
    FROM #par p
    JOIN #i d ON d.FuenteId = p.FuenteId AND d.IssueId = p.Des
    LEFT JOIN #h h ON h.FuenteId = p.FuenteId AND h.IssueId = p.Des
    LEFT JOIN #e e ON e.FuenteId = p.FuenteId AND e.IssueId = p.Des
    GROUP BY p.FuenteId, p.Anc;

    SELECT x.Nodo, x.PadreNodo, x.Nivel, x.Clave, x.Elemento, x.Tipo, x.Estado, x.Responsable,
           CAST(x.SegReg / 3600.0 AS decimal(12,2)) AS HorasRegistradas,
           CAST(x.SegAut / 3600.0 AS decimal(12,2)) AS HorasAutomaticas,
           CAST(x.SegPropio / 3600.0 AS decimal(12,2)) AS HorasPropias,
           CAST(x.Est / 3600.0 AS decimal(12,2)) AS HorasEstimadas,
           CAST(CASE WHEN x.Est > 0 THEN 100.0 * ISNULL(x.SegReg, 0) / x.Est END AS decimal(9,1)) AS PorcentajeConsumido,
           x.Elementos, x.Abiertos, x.Ultimo AS UltimoRegistro
    FROM (
        -- El proyecto completo
        SELECT N'#proyecto' AS Nodo, CAST(NULL AS nvarchar(60)) AS PadreNodo, 0 AS Nivel, CAST(NULL AS varchar(50)) AS Clave,
               CAST(@Proyecto + N' · ' + MAX(i.ProyectoNombre) AS nvarchar(400)) AS Elemento, N'Proyecto' AS Tipo,
               CAST(NULL AS nvarchar(100)) AS Estado, CAST(NULL AS nvarchar(255)) AS Responsable,
               (SELECT SUM(SegReg) FROM #h) AS SegReg, (SELECT SUM(SegAut) FROM #h) AS SegAut, CAST(NULL AS bigint) AS SegPropio,
               (SELECT SUM(EstEf) FROM #e) AS Est, (SELECT MAX(Ultimo) FROM #h) AS Ultimo,
               COUNT(*) AS Elementos, SUM(CASE WHEN i.Abierto = 1 THEN 1 ELSE 0 END) AS Abiertos, '0' AS Ruta
        FROM #i i
        UNION ALL
        -- Tareas (y subtareas sueltas) sin épica
        SELECT N'#sin-epica', N'#proyecto', 1, NULL, N'(Sin épica)', N'Agrupador', NULL, NULL,
               SUM(t.SegReg), SUM(t.SegAut), NULL, SUM(t.Est), MAX(t.Ultimo), SUM(t.Elementos), SUM(t.Abiertos), '2'
        FROM #n n JOIN #t t ON t.FuenteId = n.FuenteId AND t.IssueId = n.IssueId
        WHERE n.PadreNodo = N'#sin-epica'
        HAVING COUNT(*) > 0
        UNION ALL
        SELECT CAST(n.Clave AS nvarchar(60)), n.PadreNodo, n.Nivel, n.Clave, i.Resumen, i.TipoIssue, i.Estado, i.Responsable,
               t.SegReg, t.SegAut, h.SegReg, t.Est, t.Ultimo, t.Elementos, t.Abiertos, n.Ruta
        FROM #n n
        JOIN #i i ON i.FuenteId = n.FuenteId AND i.IssueId = n.IssueId
        JOIN #t t ON t.FuenteId = n.FuenteId AND t.IssueId = n.IssueId
        LEFT JOIN #h h ON h.FuenteId = n.FuenteId AND h.IssueId = n.IssueId
    ) x
    WHERE @SoloConHoras = 0 OR x.Nivel = 0 OR ISNULL(x.SegReg, 0) + ISNULL(x.SegAut, 0) > 0
    ORDER BY x.Ruta;
END;
GO
