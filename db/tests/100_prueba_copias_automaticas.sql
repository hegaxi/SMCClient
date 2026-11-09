/* Copias automáticas de worklogs. En smco, Automation for Jira replica cada worklog que una persona registra en una
   subtarea hacia su tarea, su épica y el ticket de la OC en la mesa de servicio (mismo tiempo, creado al mismo minuto).
   Antes los reportes sumaban original + copias: el mismo trabajo contaba 3 o 4 veces y aparecía a nombre del
   responsable de la épica. Verifica:
     - qué automáticos se marcan como copia (con su original, o como "hermanas" si el original se editó) y cuáles no;
     - el resumen por issue (registradas, automáticas sin copias, copiadas aparte);
     - Horas por persona (árbol y tabla) y Horas por proyecto sin las copias.
     - casos borde (proyecto CPZ): original editado con una sola copia, coincidencia de tiempo sin relación y
       original borrado.
   Datos propios en una fuente "copias" (se borran al final). Ejecutar sobre una base desplegada. */
SET NOCOUNT ON;
GO
IF SCHEMA_ID('prueba') IS NULL EXEC ('CREATE SCHEMA prueba');
GO
CREATE OR ALTER PROCEDURE prueba.Afirmar @Condicion bit, @Mensaje nvarchar(400)
AS
BEGIN
    IF ISNULL(@Condicion, 0) = 0 BEGIN DECLARE @m nvarchar(500) = N'FALLÓ: ' + @Mensaje; THROW 50999, @m, 1; END;
    PRINT N'ok  ' + @Mensaje;
END;
GO

/* ===== Datos ===== */
DECLARE @r TABLE (FuenteId int);
INSERT @r EXEC sync.Fuente_Registrar @Codigo = 'copias', @UrlBase = N'https://copias.example';
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'copias');
INSERT ops.Proyecto (FuenteId, ProyectoId, Clave, Nombre, TipoProyecto) VALUES
 (@f, '9101', 'CPY', N'Scrum copias', 'software'),
 (@f, '9102', 'MDC', N'Mesa copias', 'service_desk'),
 (@f, '9103', 'CPZ', N'Casos borde de copias', 'software');
INSERT ops.Estado (FuenteId, EstadoId, Nombre, Categoria) VALUES (@f, '3', N'In Progress', 'indeterminate');
INSERT ops.Usuario (FuenteId, AccountId, Nombre, TipoCuenta, Activo) VALUES
 (@f, 'cp-ana',  N'Ana Copias',  'atlassian', 1),
 (@f, 'cp-beto', N'Beto Copias', 'atlassian', 1),
 (@f, 'cp-auto', N'Automation for Jira', 'app', 1);
INSERT ops.Issue (FuenteId, IssueId, Clave, ProyectoId, TipoIssue, EstadoId, CategoriaEstado, EsSubtarea, NivelJerarquia, PadreId, ResponsableId, Creado, Resumen) VALUES
 (@f, '201', 'CPY-1', '9101', N'Epic',     '3', 'indeterminate', 0,  1, NULL,  'cp-beto', '2026-02-01T10:00:00-06:00', N'Épica de la OC MDC-1'),
 (@f, '202', 'CPY-2', '9101', N'Task',     '3', 'indeterminate', 0,  0, '201', 'cp-beto', '2026-02-01T10:00:00-06:00', N'Desarrollo'),
 (@f, '203', 'CPY-3', '9101', N'Sub-task', '3', 'indeterminate', 1, -1, '202', 'cp-ana',  '2026-02-01T10:00:00-06:00', N'Subtarea de Ana'),
 (@f, '204', 'CPY-4', '9101', N'Task',     '3', 'indeterminate', 0,  0, NULL,  'cp-beto', '2026-02-01T10:00:00-06:00', N'Tarea con tiempo automático real'),
 (@f, '301', 'MDC-1', '9102', N'OC',       '3', 'indeterminate', 0,  0, NULL,  'cp-beto', '2026-02-01T10:00:00-06:00', N'OC en la mesa de servicio'),
 (@f, '402', 'CPZ-2', '9103', N'Task',     '3', 'indeterminate', 0,  0, NULL,  'cp-beto', '2026-02-01T10:00:00-06:00', N'Tarea'),
 (@f, '403', 'CPZ-3', '9103', N'Sub-task', '3', 'indeterminate', 1, -1, '402', 'cp-ana',  '2026-02-01T10:00:00-06:00', N'Subtarea de Ana'),
 (@f, '404', 'CPZ-4', '9103', N'Task',     '3', 'indeterminate', 0,  0, NULL,  'cp-beto', '2026-02-01T10:00:00-06:00', N'Tarea de Beto'),
 (@f, '405', 'CPZ-5', '9103', N'Task',     '3', 'indeterminate', 0,  0, NULL,  'cp-ana',  '2026-02-01T10:00:00-06:00', N'Tarea sin relación');

INSERT ops.Worklog (FuenteId, WorklogId, IssueId, AutorId, Inicio, Segundos, Creado) VALUES
 -- Ana registra 8 h en su subtarea; la automatización lo copia a la tarea, la épica y la OC.
 (@f, 'cp-m1', '203', 'cp-ana',  '2026-03-02T09:00:00-06:00', 28800, '2026-03-02T10:00:00-06:00'),
 (@f, 'cp-c1', '202', 'cp-auto', '2026-03-02T09:00:00-06:00', 28800, '2026-03-02T10:00:30-06:00'),
 (@f, 'cp-c2', '201', 'cp-auto', '2026-03-02T09:00:00-06:00', 28800, '2026-03-02T10:00:40-06:00'),
 (@f, 'cp-c3', '301', 'cp-auto', '2026-03-02T09:00:00-06:00', 28800, '2026-03-02T10:00:50-06:00'),
 -- Ana registró 4 h y luego las corrigió a 3: las copias (4 h) ya no coinciden con el original, pero son hermanas.
 (@f, 'cp-m2', '203', 'cp-ana',  '2026-03-03T09:00:00-06:00', 10800, '2026-03-03T10:00:00-06:00'),
 (@f, 'cp-c4', '202', 'cp-auto', '2026-03-03T09:00:00-06:00', 14400, '2026-03-03T10:00:20-06:00'),
 (@f, 'cp-c5', '201', 'cp-auto', '2026-03-03T09:00:00-06:00', 14400, '2026-03-03T10:00:30-06:00'),
 -- Tiempo automático que NO es copia de nada: sí cuenta.
 (@f, 'cp-a1', '204', 'cp-auto', '2026-03-05T12:00:00-06:00', 7200,  '2026-03-05T12:00:00-06:00'),
 -- CPZ: Ana registró 8 h y después las corrigió a 4; solo hubo UNA copia (8 h). Se reconoce por el inicio y la creación.
 (@f, 'cp-m3', '403', 'cp-ana',  '2026-04-01T09:00:00.412-06:00', 14400, '2026-04-01T10:00:00-06:00'),
 (@f, 'cp-c6', '402', 'cp-auto', '2026-04-01T09:00:00-06:00', 28800, '2026-04-01T10:00:05-06:00'),
 -- CPZ: Beto registra 8 h; 40 min después hay un automático de 8 h en una tarea sin relación: NO es copia (antes, ±2 h, sí).
 (@f, 'cp-m4', '404', 'cp-beto', '2026-04-02T08:00:00-06:00', 28800, '2026-04-02T12:00:00-06:00'),
 (@f, 'cp-a2', '405', 'cp-auto', '2026-04-02T13:00:00-06:00', 28800, '2026-04-02T12:40:00-06:00');
INSERT ops.Worklog (FuenteId, WorklogId, IssueId, AutorId, Inicio, Segundos, Creado, Eliminado) VALUES
 -- CPZ: Ana borró su worklog de 2 h; la copia quedó: tampoco cuenta.
 (@f, 'cp-m5', '403', 'cp-ana',  '2026-04-03T09:00:00-06:00', 7200,  '2026-04-03T10:00:00-06:00', 1),
 (@f, 'cp-c7', '402', 'cp-auto', '2026-04-03T09:00:00-06:00', 7200,  '2026-04-03T10:00:04-06:00', 0);

DECLARE @vacio sync.IdTipo;
EXEC sync.Worklog_Atribuir @FuenteId = @f, @Issues = @vacio, @Todo = 1;
EXEC sync.Resumen_Recalcular @FuenteId = @f, @Issues = @vacio, @Todo = 1;
GO

/* ===== Marcado ===== */
DECLARE @ok bit, @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'copias');
SET @ok = CASE WHEN (SELECT COUNT(*) FROM ops.Worklog WHERE FuenteId = @f AND WorklogId IN ('cp-c1', 'cp-c2', 'cp-c3') AND EsCopia = 1 AND CopiaDeWorklogId = 'cp-m1') = 3
               THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Las copias en la tarea, la épica y la OC se marcan como copia del worklog de la subtarea';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM ops.Worklog WHERE FuenteId = @f AND WorklogId IN ('cp-c4', 'cp-c5') AND EsCopia = 1 AND CopiaDeWorklogId = 'cp-m2') = 2
               THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Copias de un original editado (ya no coincide el tiempo): se reconocen por la hora de inicio';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ops.Worklog WHERE FuenteId = @f AND WorklogId = 'cp-c6' AND EsCopia = 1 AND CopiaDeWorklogId = 'cp-m3') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Una sola copia de un original editado (8 h → 4 h): es copia; no se suman 4 + 8';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ops.Worklog WHERE FuenteId = @f AND WorklogId = 'cp-a2' AND EsCopia = 0) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Mismo tiempo que el worklog de otra persona creado 40 min antes, otro inicio: no es copia';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM ops.Worklog WHERE FuenteId = @f AND WorklogId = 'cp-c7' AND EsCopia = 1 AND CopiaDeWorklogId = 'cp-m5') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Copia de un worklog que la persona borró: es copia (no cuenta)';
DECLARE @hz TABLE (Nodo nvarchar(60), PadreNodo nvarchar(60), Nivel int, NivelNombre nvarchar(20), Clave varchar(50), Elemento nvarchar(400), Tipo nvarchar(255),
                   Estado nvarchar(255), Responsable nvarchar(255), Reg decimal(12,2), Aut decimal(12,2), Cop decimal(12,2), Propias decimal(12,2),
                   Est decimal(12,2), Pct decimal(9,1), Elementos int, Abiertos int, Ultimo datetimeoffset(3));
INSERT @hz EXEC api.Horas_Arbol @Proyecto = 'CPZ';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @hz WHERE Nivel = 0 AND Reg = 12 AND Aut = 8 AND Cop = 10) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'CPZ: 12 h registradas (4 corregidas + 8 de Beto), 8 h automáticas reales, 10 h copiadas aparte';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM ops.Worklog WHERE FuenteId = @f AND WorklogId IN ('cp-m1', 'cp-m2', 'cp-a1') AND EsCopia = 0) = 3
               THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Los worklogs de personas y el automático sin original no son copia';
SET @ok = CASE WHEN (SELECT Origen FROM rpt.vWorklog WHERE FuenteId = @f AND WorklogId = 'cp-c3') = 'copia'
                AND (SELECT Origen FROM rpt.vWorklog WHERE FuenteId = @f AND WorklogId = 'cp-a1') = 'automatico' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'rpt.vWorklog: Origen = copia / automatico';

/* ===== Resumen por issue ===== */
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM rpt.vIssue WHERE FuenteId = @f AND Clave = 'CPY-1'
                            AND HorasRegistradasArbol = 11 AND HorasAutomaticasArbol IS NULL AND HorasCopiadasArbol = 24)
                AND EXISTS (SELECT 1 FROM rpt.vIssue WHERE FuenteId = @f AND Clave = 'MDC-1'
                            AND HorasRegistradasArbol IS NULL AND HorasAutomaticasArbol IS NULL AND HorasCopiadasArbol = 8)
                AND EXISTS (SELECT 1 FROM rpt.vIssue WHERE FuenteId = @f AND Clave = 'CPY-4' AND HorasAutomaticasArbol = 2) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Resumen: la épica suma 11 h reales (no 35); las copias van aparte (24 h en la épica, 8 h en la OC)';
GO

/* ===== Horas por persona ===== */
DECLARE @ok bit;
DECLARE @hp TABLE (Nodo nvarchar(300), PadreNodo nvarchar(300), Nivel int, NivelNombre nvarchar(20), Clave varchar(50), Elemento nvarchar(400), Tipo nvarchar(255),
                   Estado nvarchar(255), Reg decimal(12,2), Aut decimal(12,2), Tot decimal(12,2), Propias decimal(12,2), Issues int);
INSERT @hp EXEC api.Horas_PorPersonaArbol @Desde = '2026-03-01', @Hasta = '2026-03-31', @Proyecto = 'CPY';
SET @ok = CASE WHEN (SELECT Tot FROM @hp WHERE Nivel = 0) = 13
                AND (SELECT Reg FROM @hp WHERE NivelNombre = N'Persona' AND Elemento = N'Ana Copias') = 11
                AND (SELECT Tot FROM @hp WHERE NivelNombre = N'Persona' AND Elemento = N'Beto Copias') = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por persona (árbol): total 13 h; Beto (responsable de la épica) solo tiene su tiempo automático real';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @hp WHERE Clave = 'CPY-1' AND Nivel = 3 AND Reg = 11 AND Propias IS NULL)
                AND EXISTS (SELECT 1 FROM @hp WHERE Clave = 'CPY-3' AND Nivel = 5 AND Reg = 11 AND Propias = 11)
                AND NOT EXISTS (SELECT 1 FROM @hp x JOIN @hp p ON p.NivelNombre = N'Persona' AND p.Elemento = N'Beto Copias'
                                WHERE x.Clave = 'CPY-1' AND x.Nodo LIKE p.Nodo + N'|%') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'La épica se desglosa hasta la subtarea de Ana; no aparece a nombre del responsable';

DECLARE @h TABLE (Persona nvarchar(255), Proyecto varchar(50), TipoProyecto varchar(30), Issues int, Reg decimal(12,2), Aut decimal(12,2), Tot decimal(12,2));
INSERT @h EXEC api.Horas_PorPersona @Desde = '2026-03-01', @Hasta = '2026-03-31', @Proyecto = 'MDC';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @h) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por persona (tabla): la OC no suma las copias';
DELETE @h;
INSERT @h EXEC api.Horas_PorPersona @Desde = '2026-03-01', @Hasta = '2026-03-31', @Proyecto = 'CPY';
SET @ok = CASE WHEN (SELECT SUM(Tot) FROM @h) = 13 AND (SELECT SUM(Aut) FROM @h) = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por persona (tabla): 11 h registradas + 2 h automáticas reales';
GO

/* ===== Horas por proyecto ===== */
DECLARE @ok bit;
DECLARE @a TABLE (Nodo nvarchar(60), PadreNodo nvarchar(60), Nivel int, NivelNombre nvarchar(20), Clave varchar(50), Elemento nvarchar(400), Tipo nvarchar(255),
                  Estado nvarchar(255), Responsable nvarchar(255), Reg decimal(12,2), Aut decimal(12,2), Cop decimal(12,2), Propias decimal(12,2),
                  Est decimal(12,2), Pct decimal(9,1), Elementos int, Abiertos int, Ultimo datetimeoffset(3));
INSERT @a EXEC api.Horas_Arbol @Proyecto = 'CPY';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @a WHERE Nivel = 0 AND Reg = 11 AND Aut = 2 AND Cop = 24)
                AND EXISTS (SELECT 1 FROM @a WHERE Clave = 'CPY-1' AND Reg = 11 AND Aut IS NULL AND Cop = 24) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por proyecto: registradas y automáticas sin copias; las copias en su columna';
DELETE @a;
INSERT @a EXEC api.Horas_Arbol @Proyecto = 'MDC';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @a WHERE Clave = 'MDC-1' AND Reg IS NULL AND Cop = 8) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por proyecto: la OC se muestra con sus 8 h copiadas (no queda vacía)';
GO

/* ===== Limpieza ===== */
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'copias');
DELETE ops.IssueResumen WHERE FuenteId = @f;
DELETE ops.Worklog WHERE FuenteId = @f;
DELETE ops.Issue WHERE FuenteId = @f;
DELETE ops.Usuario WHERE FuenteId = @f;
DELETE ops.Estado WHERE FuenteId = @f;
DELETE ops.Proyecto WHERE FuenteId = @f;
DELETE cfg.EntidadSync WHERE FuenteId = @f;
DELETE cfg.Fuente WHERE FuenteId = @f;
GO
DROP PROCEDURE prueba.Afirmar;
PRINT N'TODAS LAS PRUEBAS DE COPIAS AUTOMÁTICAS PASARON';
GO
