/* Datos sintéticos para la prueba de carga (fuente "carga"), con la forma del Jira real de smco:
   - Scrum: 300 épicas, 2 700 tareas (hijas de épicas) y 2 000 subtareas (hijas de tareas), en 26 sprints de 2 semanas.
   - Mesa de ayuda: 3 000 tickets con 2 SLA cada uno.
   - ~515 000 worklogs: Automation for Jira registra 8 h por día en tareas y épicas (lo que más volumen genera) y las
     personas registran en las subtareas y los tickets.
   - Historial: 3 cambios de responsable por tarea/épica (la atribución de horas automáticas lo usa) y cambios de estado.
   Se inserta directo en ops.* (no pasa por raw: se mide la consulta, no la integración). Tarda ~1-2 min.
   Uso: sqlcmd -d SMCClient -b -I -i tests/carga/010_generar_datos.sql   (la base debe estar desplegada) */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF EXISTS (SELECT 1 FROM cfg.Fuente WHERE Codigo = 'carga') THROW 50000, 'Ya hay datos de carga: use una base nueva.', 1;
DECLARE @x TABLE (FuenteId int);
INSERT @x EXEC sync.Fuente_Registrar @Codigo = 'carga', @UrlBase = N'https://carga.atlassian.net';
GO
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'carga');
DECLARE @hoy datetimeoffset(3) = DATEADD(HOUR, 9, CAST(CAST(SYSDATETIMEOFFSET() AS date) AS datetimeoffset(3)));
DECLARE @t0 datetime2 = SYSDATETIME();

-- Números 1..1 000 000
SELECT TOP (1000000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS int) AS n INTO #n
FROM sys.all_columns a CROSS JOIN sys.all_columns b CROSS JOIN sys.all_columns c;
CREATE UNIQUE CLUSTERED INDEX ix ON #n (n);

INSERT ops.Proyecto (FuenteId, ProyectoId, Clave, Nombre, TipoProyecto, Estilo, Eliminado, Actualizado) VALUES
 (@f, '91000', 'CSCR', N'Scrum carga A', 'software', 'classic', 0, @hoy), (@f, '91001', 'CSCA', N'Scrum carga B', 'software', 'classic', 0, @hoy),
 (@f, '91002', 'CMDA', N'Mesa carga A', 'service_desk', 'classic', 0, @hoy), (@f, '91003', 'CMDB', N'Mesa carga B', 'service_desk', 'classic', 0, @hoy);
INSERT ops.Estado (FuenteId, EstadoId, Nombre, Categoria, Actualizado) VALUES
 (@f, '1', N'Por Hacer', 'new', @hoy), (@f, '3', N'En Progreso', 'indeterminate', @hoy), (@f, '10001', N'Done', 'done', @hoy);
INSERT ops.Usuario (FuenteId, AccountId, Nombre, TipoCuenta, Activo, Actualizado)
SELECT @f, CONCAT('u', n), CONCAT(N'Persona ', n), 'atlassian', 1, @hoy FROM #n WHERE n <= 40
UNION ALL SELECT @f, 'auto', N'Automation for Jira', 'app', 1, @hoy;

/* Issues: 1-300 épicas, 301-3000 tareas, 3001-5000 subtareas, 5001-8000 tickets de mesa de ayuda. */
INSERT ops.Issue (FuenteId, IssueId, Clave, ProyectoId, TipoIssueId, TipoIssue, EstadoId, CategoriaEstado, PrioridadId, Prioridad,
                  ResponsableId, InformanteId, Resumen, PadreClave, PadreId, EsSubtarea, NivelJerarquia, StoryPoints,
                  EstimacionOriginalSeg, Creado, Actualizado, Resuelto, TipoSolicitudId, TipoSolicitud)
SELECT @f, CAST(100000 + n AS varchar(30)), CONCAT(p.Clave, '-', n), p.ProyectoId,
       t.TipoId, t.Tipo,
       e.EstadoId, e.Categoria, CAST(1 + n % 4 AS varchar(30)), CHOOSE(1 + n % 4, N'Highest', N'High', N'Medium', N'Low'),
       CONCAT('u', 1 + n % 40), CONCAT('u', 1 + (n * 7) % 40),
       CONCAT(t.Tipo, N' de carga ', n, CASE WHEN n % 5 = 0 THEN N' inventario' WHEN n % 5 = 1 THEN N' reportes' ELSE N'' END),
       pa.PadreClave, pa.PadreId, CAST(CASE WHEN n BETWEEN 3001 AND 5000 THEN 1 ELSE 0 END AS bit), t.Nivel,
       CASE WHEN n BETWEEN 301 AND 3000 THEN 1 + n % 8 END,
       CASE WHEN n BETWEEN 301 AND 5000 THEN 3600 * (2 + n % 30) END,
       c.Creado, DATEADD(DAY, (n % 20), c.Creado),
       CASE WHEN e.Categoria = 'done' THEN DATEADD(DAY, (n % 20), c.Creado) END,
       CASE WHEN n > 5000 THEN CAST(700 + n % 5 AS varchar(30)) END, CASE WHEN n > 5000 THEN CONCAT(N'Solicitud ', n % 5) END
FROM #n
CROSS APPLY (SELECT CASE WHEN n <= 5000 THEN CASE WHEN n % 2 = 0 THEN 'CSCR' ELSE 'CSCA' END ELSE CASE WHEN n % 2 = 0 THEN 'CMDA' ELSE 'CMDB' END END AS Clave) pk
JOIN ops.Proyecto p ON p.FuenteId = @f AND p.Clave = pk.Clave
CROSS APPLY (SELECT CASE WHEN n <= 300 THEN '10000' WHEN n <= 3000 THEN '10007' WHEN n <= 5000 THEN '10003' ELSE '10005' END AS TipoId,
                    CASE WHEN n <= 300 THEN N'Epic' WHEN n <= 3000 THEN N'Task' WHEN n <= 5000 THEN N'Subtarea' ELSE N'Incidente' END AS Tipo,
                    CAST(CASE WHEN n <= 300 THEN 1 WHEN n BETWEEN 3001 AND 5000 THEN -1 ELSE 0 END AS smallint) AS Nivel) t
CROSS APPLY (SELECT CASE WHEN n % 10 < 6 THEN '10001' WHEN n % 10 < 8 THEN '3' ELSE '1' END AS EstadoId,
                    CASE WHEN n % 10 < 6 THEN 'done' WHEN n % 10 < 8 THEN 'indeterminate' ELSE 'new' END AS Categoria) e
CROSS APPLY (SELECT DATEADD(DAY, -(n % 365) - 30, @hoy) AS Creado) c
CROSS APPLY (SELECT CASE WHEN n BETWEEN 301 AND 3000 THEN 1 + (n - 301) % 300
                         WHEN n BETWEEN 3001 AND 5000 THEN 301 + (n - 3001) % 2700 END AS np) x
OUTER APPLY (SELECT CAST(100000 + x.np AS varchar(30)) AS PadreId,
                    CONCAT(CASE WHEN x.np % 2 = 0 THEN 'CSCR' ELSE 'CSCA' END, '-', x.np) AS PadreClave WHERE x.np IS NOT NULL) pa
WHERE n <= 8000;

/* Sprints: 26 de 2 semanas hacia atrás; el último activo. Tareas en 1 a 3 sprints; subtareas en los de su tarea. */
INSERT ops.Sprint (FuenteId, SprintId, Nombre, Estado, TableroId, Inicio, Fin, Completado, Actualizado)
SELECT @f, 5000 + n, CONCAT(N'Sprint C', n), CASE WHEN n = 26 THEN 'active' ELSE 'closed' END, 700,
       DATEADD(DAY, (n - 26) * 14 - 13, @hoy), DATEADD(DAY, (n - 26) * 14, @hoy),
       CASE WHEN n < 26 THEN DATEADD(DAY, (n - 26) * 14, @hoy) END, @hoy
FROM #n WHERE n <= 26;
INSERT ops.IssueSprint (IssueSk, FuenteId, SprintId)
SELECT DISTINCT i.IssueSk, @f, s.SprintId
FROM ops.Issue i
CROSS APPLY (SELECT CAST(i.IssueId AS int) - 100000 AS k) k
CROSS APPLY (SELECT CASE WHEN k.k BETWEEN 3001 AND 5000 THEN 301 + (k.k - 3001) % 2700 ELSE k.k END AS tarea) t
CROSS JOIN (VALUES (0), (1), (2)) v(o)
JOIN ops.Sprint s ON s.FuenteId = @f AND s.SprintId = 5001 + (t.tarea + v.o) % 26
WHERE i.FuenteId = @f AND k.k BETWEEN 301 AND 5000 AND v.o <= t.tarea % 3;

/* Worklogs. Automation: 8 h por día (150 días) en cada tarea y épica. Personas: 25 en cada subtarea y 5 por ticket. */
SELECT IDENTITY(int, 1, 1) AS id, IssueId, AutorId, Inicio, Segundos INTO #w FROM (
    SELECT i.IssueId, 'auto' AS AutorId, DATEADD(HOUR, -1, DATEADD(DAY, d.n - 1, i.Creado)) AS Inicio, 28800 AS Segundos
    FROM ops.Issue i JOIN #n d ON d.n <= 150 WHERE i.FuenteId = @f AND i.NivelJerarquia >= 0 AND CAST(i.IssueId AS int) <= 103000
    UNION ALL
    SELECT i.IssueId, CONCAT('u', 1 + (CAST(i.IssueId AS int) + d.n) % 40), DATEADD(HOUR, 2, DATEADD(DAY, d.n, i.Creado)), 3600 * (1 + d.n % 4)
    FROM ops.Issue i JOIN #n d ON d.n <= 25 WHERE i.FuenteId = @f AND i.NivelJerarquia = -1
    UNION ALL
    SELECT i.IssueId, CONCAT('u', 1 + (CAST(i.IssueId AS int) + d.n) % 40), DATEADD(HOUR, 3, DATEADD(DAY, d.n, i.Creado)), 1800 * d.n
    FROM ops.Issue i JOIN #n d ON d.n <= 5 WHERE i.FuenteId = @f AND CAST(i.IssueId AS int) > 105000
) w;
INSERT ops.Worklog (FuenteId, WorklogId, IssueId, AutorId, ActualizadoPorId, Inicio, Segundos, Creado, Actualizado)
SELECT @f, CAST(2000000 + id AS varchar(30)), IssueId, AutorId, AutorId, Inicio, Segundos, Inicio, Inicio FROM #w;
UPDATE i SET TiempoInvertidoSeg = s.Seg
FROM ops.Issue i JOIN (SELECT IssueId, SUM(CAST(Segundos AS bigint)) AS Seg FROM ops.Worklog WHERE FuenteId = @f GROUP BY IssueId) s ON s.IssueId = i.IssueId
WHERE i.FuenteId = @f;

/* Historial: 3 cambios de responsable por tarea/épica y 2 de estado por issue. */
INSERT ops.IssueCambio (FuenteId, HistoriaId, Orden, IssueSk, Fecha, AutorId, CampoId, Campo, Desde, DesdeTexto, Hacia, HaciaTexto)
SELECT @f, CONCAT('a', i.IssueSk, '-', v.o), 0, i.IssueSk, DATEADD(DAY, 30 * v.o, i.Creado), 'u1', 'assignee', N'assignee',
       CONCAT('u', 1 + (i.IssueSk + v.o - 1) % 40), NULL, CONCAT('u', 1 + (i.IssueSk + v.o) % 40), NULL
FROM ops.Issue i CROSS JOIN (VALUES (1), (2), (3)) v(o)
WHERE i.FuenteId = @f AND i.NivelJerarquia >= 0 AND CAST(i.IssueId AS int) <= 103000
UNION ALL
SELECT @f, CONCAT('s', i.IssueSk, '-', v.o), 0, i.IssueSk, DATEADD(DAY, 3 * v.o, i.Creado), 'u2', 'status', N'status',
       CASE v.o WHEN 1 THEN '1' ELSE '3' END, NULL, CASE v.o WHEN 1 THEN '3' ELSE i.EstadoId END, NULL
FROM ops.Issue i CROSS JOIN (VALUES (1), (2)) v(o) WHERE i.FuenteId = @f;

/* SLA de los tickets (2 por ticket; 15 % incumplidos) y etiquetas en un tercio de los issues. */
INSERT ops.IssueSla (IssueSk, SlaId, Ciclo, Nombre, EnCurso, Inicio, Fin, Vencimiento, ObjetivoMs, TranscurridoMs, RestanteMs, Incumplido, Pausado, EnHorarioLaboral)
SELECT i.IssueSk, v.SlaId, 0, v.Nombre, CASE WHEN i.CategoriaEstado = 'done' THEN 0 ELSE 1 END, i.Creado,
       CASE WHEN i.CategoriaEstado = 'done' THEN i.Resuelto END, DATEADD(HOUR, v.Horas, i.Creado), v.Horas * 3600000, v.Horas * 3000000,
       v.Horas * 600000, CAST(CASE WHEN i.IssueSk % 7 = 0 THEN 1 ELSE 0 END AS bit), 0, 1
FROM ops.Issue i CROSS JOIN (VALUES ('86', N'Time to resolution', 24), ('87', N'Time to first response', 4)) v(SlaId, Nombre, Horas)
WHERE i.FuenteId = @f AND CAST(i.IssueId AS int) > 105000;
INSERT ops.IssueCampoValor (IssueSk, CampoId, Orden, ValorTexto)
SELECT i.IssueSk, 'labels', 0, CHOOSE(1 + i.IssueSk % 4, N'urgente', N'inventario', N'reportes', N'seguridad')
FROM ops.Issue i WHERE i.FuenteId = @f AND i.IssueSk % 3 = 0;

/* La fuente queda "sincronizada" (primera carga completa). */
INSERT sync.Ejecucion (FuenteId, Entidad, Modo, Inicio, Fin, Estado, Mensaje)
SELECT @f, e.Entidad, 'inicial', @hoy, @hoy, 'ok', N'datos sintéticos' FROM cfg.EntidadSync e WHERE e.FuenteId = @f;

UPDATE STATISTICS ops.Issue; UPDATE STATISTICS ops.Worklog; UPDATE STATISTICS ops.IssueCambio; UPDATE STATISTICS ops.IssueSprint;

/* Datos derivados (lo que hace la integración al terminar cada corrida): atribución de los 515 000 worklogs y
   resumen por issue. Se mide porque es el costo de un recálculo completo (después de una migración o un reproceso). */
DECLARE @vacio sync.IdTipo, @t1 datetime2 = SYSDATETIME(), @t2 datetime2;
EXEC sync.Worklog_Atribuir @FuenteId = @f, @Issues = @vacio, @Todo = 1;
SET @t2 = SYSDATETIME();
EXEC sync.Resumen_Recalcular @FuenteId = @f, @Issues = @vacio, @Todo = 1;
PRINT CONCAT(N'MEDICION|Recálculo completo: atribución de worklogs|', DATEDIFF(MILLISECOND, @t1, @t2), N'|', DATEDIFF(MILLISECOND, @t1, @t2), N'|60000|', CASE WHEN DATEDIFF(MILLISECOND, @t1, @t2) <= 60000 THEN N'ok' ELSE N'EXCEDE' END);
PRINT CONCAT(N'MEDICION|Recálculo completo: resumen por issue|', DATEDIFF(MILLISECOND, @t2, SYSDATETIME()), N'|', DATEDIFF(MILLISECOND, @t2, SYSDATETIME()), N'|60000|', CASE WHEN DATEDIFF(MILLISECOND, @t2, SYSDATETIME()) <= 60000 THEN N'ok' ELSE N'EXCEDE' END);
-- Recálculo incremental típico de una corrida: 50 issues tocados.
DECLARE @tocados sync.IdTipo; INSERT @tocados SELECT TOP (50) IssueId FROM ops.Issue WHERE FuenteId = @f ORDER BY IssueSk DESC;
SET @t1 = SYSDATETIME();
EXEC sync.Worklog_Atribuir @FuenteId = @f, @Issues = @tocados;
EXEC sync.Resumen_Recalcular @FuenteId = @f, @Issues = @tocados;
PRINT CONCAT(N'MEDICION|Recálculo por corrida (50 issues tocados)|', DATEDIFF(MILLISECOND, @t1, SYSDATETIME()), N'|', DATEDIFF(MILLISECOND, @t1, SYSDATETIME()), N'|5000|', CASE WHEN DATEDIFF(MILLISECOND, @t1, SYSDATETIME()) <= 5000 THEN N'ok' ELSE N'EXCEDE' END);
UPDATE STATISTICS ops.Worklog; UPDATE STATISTICS ops.IssueResumen;
SELECT (SELECT COUNT(*) FROM ops.Issue WHERE FuenteId = @f) AS Issues,
       (SELECT COUNT(*) FROM ops.Worklog WHERE FuenteId = @f) AS Worklogs,
       (SELECT COUNT(*) FROM ops.Worklog w JOIN ops.Usuario u ON u.FuenteId = w.FuenteId AND u.AccountId = w.AutorId WHERE w.FuenteId = @f AND u.TipoCuenta = 'app') AS Automaticos,
       (SELECT COUNT(*) FROM ops.IssueCambio WHERE FuenteId = @f) AS Cambios,
       (SELECT COUNT(*) FROM ops.IssueSprint WHERE FuenteId = @f) AS IssueSprint,
       DATEDIFF(SECOND, @t0, SYSDATETIME()) AS Segundos;
GO
