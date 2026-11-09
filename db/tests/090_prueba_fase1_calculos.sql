/* Fase 1: cálculos que daban cifras engañosas. Datos propios en una fuente "fase1" (se borran al final):
   - Avance de sprints con el estado AL CIERRE (no el de hoy), compromiso, agregados, arrastres, y horas sin repetir cuando
     dos sprints se traslapan.
   - Estimación del árbol sin sumar la del padre y la de sus subtareas.
   - Cumplimiento de SLA como JSM (los ciclos en curso sin vencer no cuentan como cumplidos).
   - Resumen de búsqueda: fechas en orden cronológico y horas de un periodo sin repetir.
   Ejecutar sobre una base desplegada (no depende de las otras pruebas). */
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
INSERT @r EXEC sync.Fuente_Registrar @Codigo = 'fase1', @UrlBase = N'https://fase1.example';
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'fase1');
INSERT cfg.MapeoCampo (FuenteId, Rol, CampoId, Origen) VALUES (@f, 'sprint', 'customfield_10020', 'manual');
INSERT ops.Proyecto (FuenteId, ProyectoId, Clave, Nombre, TipoProyecto) VALUES (@f, '9001', 'FAS', N'Fase 1', 'software');
INSERT ops.Estado (FuenteId, EstadoId, Nombre, Categoria) VALUES (@f, '1', N'To Do', 'new'), (@f, '3', N'In Progress', 'indeterminate'), (@f, '5', N'Done', 'done');
INSERT ops.Sprint (FuenteId, SprintId, Nombre, Estado, TableroId, Inicio, Fin, Completado) VALUES
 (@f, 8801, N'FAS Sprint 1', 'closed', 77, '2026-01-01T09:00:00-06:00', '2026-01-14T18:00:00-06:00', '2026-01-15T10:00:00-06:00'),
 -- El Sprint 2 empieza antes de que se cierre el 1 (traslape, como pasa en Jira).
 (@f, 8802, N'FAS Sprint 2', 'closed', 77, '2026-01-14T09:00:00-06:00', '2026-01-28T18:00:00-06:00', '2026-01-29T10:00:00-06:00');

INSERT ops.Issue (FuenteId, IssueId, Clave, ProyectoId, TipoIssue, EstadoId, CategoriaEstado, EsSubtarea, NivelJerarquia, PadreId, EstimacionOriginalSeg, Creado, Resumen) VALUES
 (@f, '91', 'FAS-1', '9001', N'Task',     '5', 'done',          0,  0, NULL, 36000, '2025-12-01T10:00:00-06:00', N'Terminada en el Sprint 2 (arrastrada del 1)'),
 (@f, '92', 'FAS-2', '9001', N'Task',     '5', 'done',          0,  0, NULL, NULL,  '2026-01-02T10:00:00-06:00', N'Terminada en el Sprint 1'),
 (@f, '93', 'FAS-3', '9001', N'Task',     '5', 'done',          0,  0, NULL, NULL,  '2025-11-01T10:00:00-06:00', N'Ya estaba terminada al empezar'),
 (@f, '94', 'FAS-4', '9001', N'Task',     '3', 'indeterminate', 0,  0, NULL, NULL,  '2026-01-03T10:00:00-06:00', N'Agregada a mitad del Sprint 1'),
 (@f, '95', 'FAS-5', '9001', N'Sub-task', '5', 'done',          1, -1, '91', 21600, '2026-01-05T10:00:00-06:00', N'Subtarea de FAS-1');
DECLARE @i1 bigint = (SELECT IssueSk FROM ops.Issue WHERE FuenteId = @f AND IssueId = '91'),
        @i2 bigint = (SELECT IssueSk FROM ops.Issue WHERE FuenteId = @f AND IssueId = '92'),
        @i3 bigint = (SELECT IssueSk FROM ops.Issue WHERE FuenteId = @f AND IssueId = '93'),
        @i4 bigint = (SELECT IssueSk FROM ops.Issue WHERE FuenteId = @f AND IssueId = '94'),
        @i5 bigint = (SELECT IssueSk FROM ops.Issue WHERE FuenteId = @f AND IssueId = '95');
INSERT ops.IssueSprint (IssueSk, FuenteId, SprintId) VALUES
 (@i1, @f, 8801), (@i1, @f, 8802), (@i2, @f, 8801), (@i3, @f, 8801), (@i4, @f, 8801), (@i5, @f, 8801), (@i5, @f, 8802);

INSERT ops.IssueCambio (FuenteId, HistoriaId, Orden, IssueSk, Fecha, CampoId, Campo, Desde, Hacia) VALUES
 (@f, 'f1-1', 0, @i1, '2026-01-02T10:00:00-06:00', 'status', N'status', '1', '3'),
 (@f, 'f1-2', 0, @i1, '2026-01-20T10:00:00-06:00', 'status', N'status', '3', '5'),
 -- Arrastre: al cerrar el Sprint 1 Jira lo pasa al 2 (después de que el 2 empezó): no es alcance agregado.
 (@f, 'f1-3', 0, @i1, '2026-01-15T10:00:00-06:00', 'customfield_10020', N'Sprint', '8801', '8801, 8802'),
 (@f, 'f2-1', 0, @i2, '2026-01-10T10:00:00-06:00', 'status', N'status', '1', '5'),
 (@f, 'f3-1', 0, @i3, '2025-12-20T10:00:00-06:00', 'status', N'status', '1', '5'),
 (@f, 'f4-1', 0, @i4, '2026-01-06T10:00:00-06:00', 'status', N'status', '1', '3'),
 (@f, 'f4-2', 0, @i4, '2026-01-05T10:00:00-06:00', 'customfield_10020', N'Sprint', NULL, '8801');

INSERT ops.Worklog (FuenteId, WorklogId, IssueId, AutorId, Inicio, Segundos, EsAutomatico, AtribuidoAId, MetodoAtribucion) VALUES
 (@f, 'w1', '92', 'dev-f', '2026-01-05T10:00:00-06:00', 14400, 0, 'dev-f', 'autor'),   -- 4 h en el Sprint 1
 (@f, 'w2', '95', 'dev-f', '2026-01-14T12:00:00-06:00', 7200,  0, 'dev-f', 'autor');   -- 2 h en el traslape: cuentan solo en el Sprint 2

-- SLA: un ciclo cumplido, uno en curso vencido (incumplido) y uno en curso sin vencer (no se mide todavía).
INSERT ops.IssueSla (IssueSk, SlaId, Ciclo, Nombre, EnCurso, Inicio, Fin, Vencimiento, ObjetivoMs, TranscurridoMs, Incumplido, Pausado) VALUES
 (@i2, '1', 1, N'Time to resolution', 0, '2026-01-02T10:00:00-06:00', '2026-01-10T10:00:00-06:00', '2026-01-12T10:00:00-06:00', 86400000, 3600000, 0, 0),
 (@i4, '1', 1, N'Time to resolution', 1, '2026-01-03T10:00:00-06:00', NULL, '2026-01-20T10:00:00-06:00', 86400000, NULL, 0, 0),
 (@i1, '1', 1, N'Time to resolution', 1, '2026-01-03T10:00:00-06:00', NULL, '2099-01-20T10:00:00-06:00', 86400000, NULL, 0, 0);

DECLARE @vacio sync.IdTipo;
EXEC sync.Resumen_Recalcular @FuenteId = @f, @Issues = @vacio, @Todo = 1;
GO

/* ===== Estado en un momento ===== */
DECLARE @ok bit, @i1 bigint = (SELECT i.IssueSk FROM ops.Issue i JOIN cfg.Fuente f ON f.FuenteId = i.FuenteId WHERE f.Codigo = 'fase1' AND i.IssueId = '91');
SET @ok = CASE WHEN (SELECT Categoria FROM rpt.fn_CategoriaEstadoEn(@i1, '2026-01-01T00:00:00-06:00')) = 'new'
                AND (SELECT Categoria FROM rpt.fn_CategoriaEstadoEn(@i1, '2026-01-15T10:00:00-06:00')) = 'indeterminate'
                AND (SELECT Categoria FROM rpt.fn_CategoriaEstadoEn(@i1, '2026-01-21T00:00:00-06:00')) = 'done' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'fn_CategoriaEstadoEn: el estado de FAS-1 antes, durante y después según su historial';

/* ===== Avance de sprints ===== */
DECLARE @sp TABLE (SprintId bigint, Proyecto varchar(50), Sprint nvarchar(255), Estado varchar(20), Inicio datetimeoffset, Fin datetimeoffset, Completado datetimeoffset, Vencido bit,
                   Issues int, Comprometidos int, Agregados int, YaTerminados int, TermCierre int, TermComp int, Pct decimal(5,1), Arrastrados int,
                   SP decimal(9,2), SPT decimal(9,2), HorasReg decimal(12,2), HorasAut decimal(12,2), HorasEst decimal(12,2), SinEst int);
INSERT @sp EXEC api.Sprint_Avance @Proyecto = 'FAS';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @sp WHERE Sprint = N'FAS Sprint 1' AND Issues = 4 AND YaTerminados = 1 AND Agregados = 1 AND Comprometidos = 2
                                                 AND TermCierre = 2 AND TermComp = 1 AND Pct = 50 AND Arrastrados = 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Sprint 1: 4 issues, 1 ya terminado, 1 agregado, 2 comprometidos; al cierre 2 terminados (1 comprometido = 50 %), 1 arrastrado';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @sp WHERE Sprint = N'FAS Sprint 2' AND Issues = 1 AND Agregados = 0 AND Comprometidos = 1 AND TermComp = 1 AND Pct = 100) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Sprint 2: lo arrastrado del Sprint 1 cuenta como compromiso (no como agregado) y se terminó';
SET @ok = CASE WHEN (SELECT HorasReg FROM @sp WHERE Sprint = N'FAS Sprint 1') = 4 AND (SELECT HorasReg FROM @sp WHERE Sprint = N'FAS Sprint 2') = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Sprints traslapados: el worklog del traslape cuenta solo en el sprint siguiente (4 h + 2 h, no 6 h + 2 h)';

DECLARE @h TABLE (Proyecto varchar(50), Sprint nvarchar(255), Estado varchar(20), Inicio datetimeoffset, Fin datetimeoffset, Completado datetimeoffset,
                  Persona nvarchar(255), Issues int, Reg decimal(12,2), Aut decimal(12,2), Total decimal(12,2));
INSERT @h EXEC api.Horas_PorSprint @Proyecto = 'FAS';
SET @ok = CASE WHEN (SELECT SUM(Reg) FROM @h) = 6 AND (SELECT SUM(Reg) FROM @h WHERE Sprint = N'FAS Sprint 2') = 2 AND NOT EXISTS (SELECT 1 FROM @h WHERE Proyecto <> 'FAS') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por sprint: 6 h en total sin repetir, con la columna Proyecto';

/* ===== Estimación sin doble conteo ===== */
SET @ok = CASE WHEN (SELECT HorasEstimadasArbol FROM rpt.vIssue WHERE Clave = 'FAS-1') = 6 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Estimación del árbol de FAS-1: cuenta la de su subtarea (6 h), no 10 h + 6 h';

/* ===== SLA como JSM ===== */
DECLARE @sla TABLE (Proyecto varchar(50), Sla nvarchar(255), Ciclos int, Cumplidos int, Incumplidos int, EnCursoAhora int, Pct decimal(5,1), HorasProm decimal(10,2), EnCursoCerrado int);
INSERT @sla EXEC api.Sla_Resumen @Desde = '2026-01-01', @Hasta = '2026-01-31', @Proyecto = 'FAS', @TicketsSinSla = 0;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @sla WHERE Ciclos = 2 AND Cumplidos = 1 AND Incumplidos = 1 AND Pct = 50 AND EnCursoAhora = 0 AND EnCursoCerrado = 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'SLA: 1 cumplido y 1 vencido en el periodo = 50 % (el ciclo en curso sin vencer no cuenta; está en un ticket cerrado)';

DECLARE @riesgo TABLE (Situacion nvarchar(20), Clave varchar(50), Proyecto varchar(50), Resumen nvarchar(1000), PrioridadItil int, Prioridad nvarchar(100),
                       Responsable nvarchar(255), Sla nvarchar(255), Vencimiento datetimeoffset, TiempoParaVencer nvarchar(40), DiasAbierto int);
INSERT @riesgo EXEC api.Sla_EnRiesgo @Horas = 4, @Proyecto = 'FAS';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @riesgo) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'SLA por vencer: lo vencido hace meses no aparece (por omisión, solo los últimos 7 días)';
DELETE @riesgo; INSERT @riesgo EXEC api.Sla_EnRiesgo @Horas = 4, @Proyecto = 'FAS', @DiasVencido = 100000;
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @riesgo WHERE Situacion = N'Vencido' AND Clave = 'FAS-4' AND TiempoParaVencer LIKE N'hace %') = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'SLA por vencer: con más días aparece FAS-4 como Vencido, con el tiempo en texto';
SET @ok = CASE WHEN rpt.fn_DuracionTexto(130) = N'2 h 10 min' AND rpt.fn_DuracionTexto(-4560) = N'hace 3 d 4 h' AND rpt.fn_DuracionTexto(45) = N'45 min' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'fn_DuracionTexto';

/* ===== Resumen de búsqueda ===== */
DECLARE @res TABLE (Grupo nvarchar(400), Valor decimal(19,4), Issues int, Grupos int, EsOtros bit, EtqG nvarchar(200), EtqV nvarchar(200), Posicion int);
INSERT @res EXEC api.Issues_Resumir @Criterios = N'[{"campo":"proyecto","operador":"en","valores":["FAS"]}]', @AgruparPor = 'creado', @Top = 10;
SET @ok = CASE WHEN (SELECT STRING_AGG(Grupo, N',') WITHIN GROUP (ORDER BY Posicion) FROM @res) = N'2025-11,2025-12,2026-01'
                AND NOT EXISTS (SELECT 1 FROM @res WHERE EsOtros = 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Agrupado por fecha: en orden cronológico (no por cantidad) y sin "Otros"';
DELETE @res;
INSERT @res EXEC api.Issues_Resumir @Criterios = N'[{"campo":"proyecto","operador":"en","valores":["FAS"]},{"campo":"registro_fecha","operador":"entre","valor":"2026-01-01","hasta":"2026-01-31"}]',
                                    @Agregacion = 'suma', @Valor = 'horas_registradas';
SET @ok = CASE WHEN (SELECT Valor FROM @res) = 6 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas registradas en el periodo: 6 h, cada worklog una vez (los propios de FAS-2 y de la subtarea FAS-5)';

/* ===== Horas por persona en jerarquía ===== */
DECLARE @hp TABLE (Nodo nvarchar(300), PadreNodo nvarchar(300), Nivel int, NivelNombre nvarchar(20), Clave varchar(50), Elemento nvarchar(400), Tipo nvarchar(255),
                   Estado nvarchar(255), Reg decimal(12,2), Aut decimal(12,2), Tot decimal(12,2), Propias decimal(12,2), Issues int);
INSERT @hp EXEC api.Horas_PorPersonaArbol @Desde = '2026-01-01', @Hasta = '2026-01-31', @Proyecto = 'FAS';
SET @ok = CASE WHEN (SELECT Reg FROM @hp WHERE Nivel = 0) = 6 AND (SELECT Reg FROM @hp WHERE NivelNombre = N'Persona') = 6
                AND (SELECT Reg FROM @hp WHERE NivelNombre = N'Proyecto') = 6 AND (SELECT Reg FROM @hp WHERE Elemento = N'(Sin épica)') = 6 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por persona en árbol: total, persona, proyecto y "(Sin épica)" son subtotales de 6 h';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @hp WHERE Clave = 'FAS-1' AND Nivel = 4 AND Reg = 2 AND Propias IS NULL)
                AND EXISTS (SELECT 1 FROM @hp WHERE Clave = 'FAS-5' AND Nivel = 5 AND Reg = 2 AND Propias = 2 AND PadreNodo LIKE N'%|FAS-1')
                AND EXISTS (SELECT 1 FROM @hp WHERE Clave = 'FAS-2' AND Nivel = 4 AND Reg = 4) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'La subtarea cuelga de su tarea: FAS-1 suma las 2 h de FAS-5 sin tener horas propias';
GO

/* ===== Horas por sprint en jerarquía ===== */
DECLARE @ok bit;
DECLARE @hs TABLE (Nodo nvarchar(300), PadreNodo nvarchar(300), Nivel int, NivelNombre nvarchar(20), Clave varchar(50), Elemento nvarchar(400), Tipo nvarchar(255),
                   Estado nvarchar(255), Reg decimal(12,2), Aut decimal(12,2), Tot decimal(12,2), Propias decimal(12,2), Issues int);
INSERT @hs EXEC api.Horas_PorSprintArbol @Proyecto = 'FAS';
SET @ok = CASE WHEN (SELECT Tot FROM @hs WHERE Nivel = 0) = 6
                AND (SELECT Tot FROM @hs WHERE Nivel = 1 AND Elemento LIKE N'%FAS Sprint 1%') = 4
                AND (SELECT Tot FROM @hs WHERE Nivel = 1 AND Elemento LIKE N'%FAS Sprint 2%') = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por sprint (árbol): total 6 h = 4 h del Sprint 1 + 2 h del Sprint 2 (el traslape cuenta una vez)';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @hs t JOIN @hs s ON s.PadreNodo = t.Nodo
                            WHERE t.Clave = 'FAS-1' AND t.Nivel = 3 AND t.Tot = 2 AND t.Propias IS NULL AND s.Clave = 'FAS-5' AND s.Nivel = 4 AND s.Propias = 2)
                AND (SELECT COUNT(*) FROM @hs WHERE Nivel = 2) = 2 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por sprint (árbol): sprint → persona → tarea → subtarea (FAS-5 bajo FAS-1)';

/* ===== Horas por proyecto: todos los proyectos ===== */
DECLARE @a TABLE (Nodo nvarchar(60), PadreNodo nvarchar(60), Nivel int, NivelNombre nvarchar(20), Clave varchar(50), Elemento nvarchar(400), Tipo nvarchar(255),
                  Estado nvarchar(255), Responsable nvarchar(255), Reg decimal(12,2), Aut decimal(12,2), Cop decimal(12,2), Propias decimal(12,2),
                  Est decimal(12,2), Pct decimal(9,1), Elementos int, Abiertos int, Ultimo datetimeoffset(3));
INSERT @a EXEC api.Horas_Arbol @TipoProyecto = 'software', @Desde = '2026-01-01', @Hasta = '2026-01-31';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @a WHERE Nodo = N'P|FAS' AND Nivel = 1 AND Reg = 6 AND PadreNodo = N'#total')
                AND EXISTS (SELECT 1 FROM @a WHERE Nodo = N'S|FAS' AND Nivel = 2 AND Reg = 6)
                AND EXISTS (SELECT 1 FROM @a WHERE Clave = 'FAS-5' AND Nivel = 4 AND PadreNodo = N'FAS-1')
                AND (SELECT Reg FROM @a WHERE Nivel = 0) = (SELECT SUM(Reg) FROM @a WHERE Nivel = 1) THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Horas por proyecto sin elegir proyecto: Total → proyecto → (Sin épica) → tarea → subtarea, y el total suma los proyectos';
GO

/* ===== Tiempos invertidos (una columna por periodo) ===== */
DECLARE @ok bit;
DECLARE @t TABLE (Nodo nvarchar(60), PadreNodo nvarchar(60), Nivel int, NivelNombre nvarchar(30), Clave varchar(50), Elemento nvarchar(400),
                  Total decimal(12,2), Ene decimal(12,2));
INSERT @t EXEC api.Tiempos_Invertidos @Desde = '2026-01-01', @Hasta = '2026-01-31', @Proyecto = 'FAS', @Periodo = 'mes',
                                      @Categoria = 'persona', @Grupo = 'tarea';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @t WHERE Nivel = 0 AND Total = 6 AND Ene = 6)
                AND EXISTS (SELECT 1 FROM @t WHERE Nivel = 1 AND NivelNombre = N'Persona' AND Total = 6)
                AND EXISTS (SELECT 1 FROM @t WHERE Nivel = 2 AND NivelNombre = N'Tarea' AND Clave = 'FAS-1' AND Total = 2)
                AND EXISTS (SELECT 1 FROM @t WHERE Nivel = 2 AND Clave = 'FAS-2' AND Total = 4)
                AND (SELECT COUNT(*) FROM @t) = 4 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Tiempos invertidos: persona → tarea (la subtarea FAS-5 se suma en FAS-1), columna Ene 2026 y Total de 6 h';
DELETE @t;
INSERT @t EXEC api.Tiempos_Invertidos @Desde = '2026-01-01', @Hasta = '2026-01-31', @Proyecto = 'FAS', @Periodo = 'mes',
                                      @Categoria = 'ninguna', @Grupo = 'ninguna', @Unidad = 'dias';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @t) = 1 AND (SELECT Total FROM @t) = 0.75 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Tiempos invertidos en días de 8 h: 6 h = 0.75 días; sin agrupaciones solo queda el total';
DECLARE @s TABLE (Nodo nvarchar(60), PadreNodo nvarchar(60), Nivel int, NivelNombre nvarchar(30), Clave varchar(50), Elemento nvarchar(400),
                  Total decimal(12,2), Sem1 decimal(12,2), Sem2 decimal(12,2), Sem3 decimal(12,2));
INSERT @s EXEC api.Tiempos_Invertidos @Desde = '2026-01-05', @Hasta = '2026-01-21', @Proyecto = 'FAS', @Periodo = 'semana',
                                      @Categoria = 'issue', @Grupo = 'ninguna', @Sprint = N'FAS Sprint 2';
SET @ok = CASE WHEN (SELECT Total FROM @s WHERE Nivel = 0) = 2 AND (SELECT Sem2 FROM @s WHERE Nivel = 0) = 2
                AND EXISTS (SELECT 1 FROM @s WHERE Clave = 'FAS-5' AND NivelNombre = N'Ticket') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Tiempos invertidos por sprint y semana: solo las 2 h registradas en el Sprint 2 (semana del 12/01), con columnas de semanas vacías';
GO

/* ===== Limpieza ===== */
DECLARE @f int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = 'fase1');
DELETE s FROM ops.IssueSla s JOIN ops.Issue i ON i.IssueSk = s.IssueSk WHERE i.FuenteId = @f;
DELETE ops.Worklog WHERE FuenteId = @f;
DELETE ops.Issue WHERE FuenteId = @f;
DELETE ops.Sprint WHERE FuenteId = @f;
DELETE ops.Estado WHERE FuenteId = @f;
DELETE ops.Proyecto WHERE FuenteId = @f;
DELETE cfg.MapeoCampo WHERE FuenteId = @f;
DELETE cfg.EntidadSync WHERE FuenteId = @f;
DELETE cfg.Fuente WHERE FuenteId = @f;
GO
DROP PROCEDURE prueba.Afirmar;
PRINT N'TODAS LAS PRUEBAS DE CÁLCULOS (FASE 1) PASARON';
GO
