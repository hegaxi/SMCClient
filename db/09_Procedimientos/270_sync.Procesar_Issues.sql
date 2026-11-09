/* Integra issues (historias Scrum y tickets JSM) desde raw.Documento (contrato: el objeto issue de
   /rest/api/3/search/jql con fields=*all; IdExterno = id del issue).

   Cómo resiste cambios en Jira:
   1. Las columnas canónicas se leen por ROL (cfg.MapeoCampo): si el campo de un rol cambia de ID,
      solo cambia el mapeo, no este código.
   2. TODOS los campos personalizados (incluso los que aún no están en el catálogo) se copian a
      ops.IssueCampoValor según el tipo del valor JSON; lo que no se reconoce se guarda como JSON.
   3. Usuarios, sprints, estados y proyectos se descubren del propio documento. */
CREATE OR ALTER PROCEDURE sync.Procesar_Issues
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.DocumentoId, CAST(JSON_VALUE(d.Json, '$.id') AS varchar(30)) AS IssueId,
           CAST(JSON_VALUE(d.Json, '$.key') AS varchar(50)) AS Clave, d.Json
    INTO #d
    FROM #lote l JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId;

    IF EXISTS (SELECT 1 FROM #d WHERE IssueId IS NULL OR Clave IS NULL)
        THROW 50040, 'Documento de issue sin "id" o "key".', 1;

    /* 1. Valores por rol --------------------------------------------------------------------- */
    SELECT m.Rol,
           CONCAT(N'$.fields."', m.CampoId, N'"', SUBSTRING(r.RutaValor, 2, 200)) AS RutaValor,
           CASE WHEN r.RutaTexto IS NOT NULL THEN CONCAT(N'$.fields."', m.CampoId, N'"', SUBSTRING(r.RutaTexto, 2, 200)) END AS RutaTexto
    INTO #m
    FROM cfg.MapeoCampo m JOIN cfg.RolCampo r ON r.Rol = m.Rol
    WHERE m.FuenteId = @FuenteId AND m.CampoId IS NOT NULL;

    SELECT d.DocumentoId, m.Rol,
           JSON_VALUE(d.Json, m.RutaValor) AS Valor,
           CASE WHEN m.RutaTexto IS NOT NULL THEN JSON_VALUE(d.Json, m.RutaTexto) END AS Texto
    INTO #v
    FROM #d d CROSS JOIN #m m;

    -- Subtarea: se lee de issuetype.subtask (el campo del rol tipo_issue).
    DECLARE @rutaSubtarea nvarchar(300) = CONCAT(N'$.fields."',
        ISNULL((SELECT CampoId FROM cfg.MapeoCampo WHERE FuenteId = @FuenteId AND Rol = 'tipo_issue'), 'issuetype'), N'".subtask');

    SELECT d.DocumentoId, d.IssueId, d.Clave,
        CAST(MAX(CASE WHEN JSON_VALUE(d.Json, @rutaSubtarea) = 'true' THEN 1 ELSE 0 END) AS bit) AS EsSubtarea,
        MAX(CASE WHEN v.Rol = 'proyecto'            THEN v.Valor END) AS ProyectoId,
        MAX(CASE WHEN v.Rol = 'proyecto'            THEN v.Texto END) AS ProyectoClave,
        MAX(CASE WHEN v.Rol = 'tipo_issue'          THEN v.Valor END) AS TipoIssueId,
        MAX(CASE WHEN v.Rol = 'tipo_issue'          THEN v.Texto END) AS TipoIssue,
        MAX(CASE WHEN v.Rol = 'estado'              THEN v.Valor END) AS EstadoId,
        MAX(CASE WHEN v.Rol = 'estado'              THEN v.Texto END) AS Estado,
        MAX(CASE WHEN v.Rol = 'categoria_estado'    THEN v.Valor END) AS CategoriaEstado,
        MAX(CASE WHEN v.Rol = 'prioridad'           THEN v.Valor END) AS PrioridadId,
        MAX(CASE WHEN v.Rol = 'prioridad'           THEN v.Texto END) AS Prioridad,
        MAX(CASE WHEN v.Rol = 'resolucion'          THEN v.Valor END) AS ResolucionId,
        MAX(CASE WHEN v.Rol = 'resolucion'          THEN v.Texto END) AS Resolucion,
        MAX(CASE WHEN v.Rol = 'responsable'         THEN v.Valor END) AS ResponsableId,
        MAX(CASE WHEN v.Rol = 'informante'          THEN v.Valor END) AS InformanteId,
        MAX(CASE WHEN v.Rol = 'resumen'             THEN v.Valor END) AS Resumen,
        MAX(CASE WHEN v.Rol = 'padre'               THEN v.Valor END) AS PadreClave,
        MAX(CASE WHEN v.Rol = 'tipo_solicitud'      THEN v.Valor END) AS TipoSolicitudId,
        MAX(CASE WHEN v.Rol = 'tipo_solicitud'      THEN v.Texto END) AS TipoSolicitud,
        MAX(CASE WHEN v.Rol = 'story_points'        THEN v.Valor END) AS StoryPoints,
        MAX(CASE WHEN v.Rol = 'tiempo_invertido'    THEN v.Valor END) AS TiempoInvertido,
        MAX(CASE WHEN v.Rol = 'estimacion_original' THEN v.Valor END) AS EstimacionOriginal,
        MAX(CASE WHEN v.Rol = 'estimacion_restante' THEN v.Valor END) AS EstimacionRestante,
        MAX(CASE WHEN v.Rol = 'creado'              THEN v.Valor END) AS Creado,
        MAX(CASE WHEN v.Rol = 'actualizado'         THEN v.Valor END) AS Actualizado,
        MAX(CASE WHEN v.Rol = 'resuelto'            THEN v.Valor END) AS Resuelto,
        MAX(CASE WHEN v.Rol = 'vencimiento'         THEN v.Valor END) AS Vencimiento
    INTO #i
    FROM #d d LEFT JOIN #v v ON v.DocumentoId = d.DocumentoId
    GROUP BY d.DocumentoId, d.IssueId, d.Clave;

    /* Issues de proyectos excluidos: se dan por procesados sin integrarse (el worker ya los filtra en
       el JQL; esto cubre los que llegaron antes de excluir el proyecto o por un backfill). */
    DELETE i FROM #i i WHERE EXISTS (SELECT 1 FROM cfg.ProyectoExcluido x WHERE x.FuenteId = @FuenteId AND x.ProyectoClave = i.ProyectoClave);
    DELETE d FROM #d d WHERE NOT EXISTS (SELECT 1 FROM #i i WHERE i.DocumentoId = d.DocumentoId);

    /* 2. ops.Issue ---------------------------------------------------------------------------- */
    MERGE ops.Issue AS t
    USING (
        SELECT DocumentoId, IssueId, Clave,
               LEFT(ProyectoId, 30) AS ProyectoId, LEFT(TipoIssueId, 30) AS TipoIssueId, LEFT(TipoIssue, 255) AS TipoIssue,
               LEFT(EstadoId, 30) AS EstadoId, LEFT(CategoriaEstado, 20) AS CategoriaEstado,
               LEFT(PrioridadId, 30) AS PrioridadId, LEFT(Prioridad, 100) AS Prioridad,
               LEFT(ResolucionId, 30) AS ResolucionId, LEFT(Resolucion, 100) AS Resolucion,
               LEFT(ResponsableId, 128) AS ResponsableId, LEFT(InformanteId, 128) AS InformanteId,
               LEFT(Resumen, 1000) AS Resumen, LEFT(PadreClave, 50) AS PadreClave, EsSubtarea,
               LEFT(TipoSolicitudId, 30) AS TipoSolicitudId, LEFT(TipoSolicitud, 255) AS TipoSolicitud,
               TRY_CAST(TRY_CAST(StoryPoints AS float) AS decimal(9,2)) AS StoryPoints,
               TRY_CAST(TRY_CAST(TiempoInvertido AS float) AS bigint) AS TiempoInvertidoSeg,
               TRY_CAST(TRY_CAST(EstimacionOriginal AS float) AS bigint) AS EstimacionOriginalSeg,
               TRY_CAST(TRY_CAST(EstimacionRestante AS float) AS bigint) AS EstimacionRestanteSeg,
               sync.fn_FechaJira(Creado) AS Creado, sync.fn_FechaJira(Actualizado) AS Actualizado,
               sync.fn_FechaJira(Resuelto) AS Resuelto, TRY_CONVERT(date, LEFT(Vencimiento, 10), 23) AS Vencimiento
        FROM #i
    ) AS s ON t.FuenteId = @FuenteId AND t.IssueId = s.IssueId
    WHEN MATCHED THEN UPDATE SET
        Clave = s.Clave, ProyectoId = s.ProyectoId, TipoIssueId = s.TipoIssueId, TipoIssue = s.TipoIssue,
        EstadoId = s.EstadoId, CategoriaEstado = s.CategoriaEstado, PrioridadId = s.PrioridadId, Prioridad = s.Prioridad,
        ResolucionId = s.ResolucionId, Resolucion = s.Resolucion, ResponsableId = s.ResponsableId, InformanteId = s.InformanteId,
        Resumen = s.Resumen, PadreClave = s.PadreClave, EsSubtarea = s.EsSubtarea, TipoSolicitudId = s.TipoSolicitudId, TipoSolicitud = s.TipoSolicitud,
        StoryPoints = s.StoryPoints, TiempoInvertidoSeg = s.TiempoInvertidoSeg, EstimacionOriginalSeg = s.EstimacionOriginalSeg,
        EstimacionRestanteSeg = s.EstimacionRestanteSeg, Creado = s.Creado, Actualizado = s.Actualizado, Resuelto = s.Resuelto,
        Vencimiento = s.Vencimiento, Eliminado = 0, DocumentoId = s.DocumentoId, Integrado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (
        FuenteId, IssueId, Clave, ProyectoId, TipoIssueId, TipoIssue, EstadoId, CategoriaEstado, PrioridadId, Prioridad,
        ResolucionId, Resolucion, ResponsableId, InformanteId, Resumen, PadreClave, EsSubtarea, TipoSolicitudId, TipoSolicitud,
        StoryPoints, TiempoInvertidoSeg, EstimacionOriginalSeg, EstimacionRestanteSeg, Creado, Actualizado, Resuelto, Vencimiento, DocumentoId)
    VALUES (
        @FuenteId, s.IssueId, s.Clave, s.ProyectoId, s.TipoIssueId, s.TipoIssue, s.EstadoId, s.CategoriaEstado, s.PrioridadId, s.Prioridad,
        s.ResolucionId, s.Resolucion, s.ResponsableId, s.InformanteId, s.Resumen, s.PadreClave, s.EsSubtarea, s.TipoSolicitudId, s.TipoSolicitud,
        s.StoryPoints, s.TiempoInvertidoSeg, s.EstimacionOriginalSeg, s.EstimacionRestanteSeg, s.Creado, s.Actualizado, s.Resuelto, s.Vencimiento, s.DocumentoId);

    SELECT d.DocumentoId, i.IssueSk, d.Json
    INTO #k
    FROM #d d JOIN ops.Issue i ON i.FuenteId = @FuenteId AND i.IssueId = d.IssueId;

    /* 3. Valores de campos (EAV) ------------------------------------------------------------- */
    DELETE v FROM ops.IssueCampoValor v JOIN #k k ON k.IssueSk = v.IssueSk;

    INSERT ops.IssueCampoValor (IssueSk, CampoId, Orden, ValorTexto, ValorNumero, ValorFecha, ValorId, ValorJson)
    SELECT k.IssueSk, LEFT(f.[key], 100), x.Orden,
        LEFT(CASE WHEN x.t IN (1, 2, 3) THEN x.v
                  WHEN x.t = 5 THEN o.Texto END, 4000),
        CASE WHEN x.t = 2 THEN TRY_CAST(TRY_CAST(x.v AS float) AS decimal(19,4)) END,
        CASE WHEN x.t = 1 AND (c.TipoSchema IN ('date', 'datetime') OR (c.CampoId IS NULL AND x.v LIKE '[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]%'))
             THEN sync.fn_FechaJira(x.v) END,
        CASE WHEN x.t = 5 THEN LEFT(o.Id, 200) END,
        CASE WHEN x.t = 4 THEN x.v
             WHEN x.t = 5 AND (o.Id IS NULL OR o.Texto IS NULL) THEN x.v END
    FROM #k k
    CROSS APPLY OPENJSON(k.Json, '$.fields') f
    LEFT JOIN meta.CampoJira c ON c.FuenteId = @FuenteId AND c.CampoId = f.[key] COLLATE DATABASE_DEFAULT   -- OPENJSON devuelve [key] en Latin1_General_BIN2
    CROSS APPLY (
        SELECT CAST(0 AS smallint) AS Orden, f.value AS v, f.type AS t WHERE f.type IN (1, 2, 3, 5)
        UNION ALL
        SELECT CAST(a.[key] AS smallint), a.value, a.type FROM OPENJSON(CASE WHEN f.type = 4 THEN f.value END) a WHERE a.type <> 0
    ) x
    OUTER APPLY (
        SELECT COALESCE(JSON_VALUE(x.v, '$.accountId'), JSON_VALUE(x.v, '$.id'), JSON_VALUE(x.v, '$.key'), JSON_VALUE(x.v, '$.requestType.id')) AS Id,
               COALESCE(JSON_VALUE(x.v, '$.value'), JSON_VALUE(x.v, '$.name'), JSON_VALUE(x.v, '$.displayName'),
                        JSON_VALUE(x.v, '$.requestType.name'), JSON_VALUE(x.v, '$.key')) AS Texto
        WHERE x.t = 5
    ) o
    -- Campos del catálogo marcados para guardar; si el campo aún no está en el catálogo y es
    -- personalizado, también se guarda (no se pierde el valor mientras llega el catálogo).
    WHERE ISNULL(c.GuardarValor, CASE WHEN f.[key] LIKE 'customfield[_]%' THEN 1 ELSE 0 END) = 1;

    /* 4. Sprints ------------------------------------------------------------------------------ */
    DECLARE @campoSprint varchar(100) = (SELECT CampoId FROM cfg.MapeoCampo WHERE FuenteId = @FuenteId AND Rol = 'sprint');
    IF @campoSprint IS NOT NULL
    BEGIN
        DECLARE @rutaSprint nvarchar(200) = CONCAT(N'$.fields."', @campoSprint, N'"');
        SELECT k.IssueSk, s.SprintId, s.Nombre, s.Estado, s.TableroId, s.Objetivo,
               sync.fn_FechaJira(s.Inicio) AS Inicio, sync.fn_FechaJira(s.Fin) AS Fin, sync.fn_FechaJira(s.Completado) AS Completado
        INTO #s
        FROM #k k
        CROSS APPLY OPENJSON(CASE WHEN ISJSON(JSON_QUERY(k.Json, @rutaSprint)) = 1 THEN JSON_QUERY(k.Json, @rutaSprint) END)
        WITH (SprintId bigint '$.id', Nombre nvarchar(255) '$.name', Estado varchar(20) '$.state', TableroId bigint '$.boardId',
              Objetivo nvarchar(2000) '$.goal', Inicio nvarchar(60) '$.startDate', Fin nvarchar(60) '$.endDate', Completado nvarchar(60) '$.completeDate') s
        WHERE s.SprintId IS NOT NULL;

        MERGE ops.Sprint AS t
        USING (SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY SprintId ORDER BY IssueSk DESC) AS rn FROM #s) q WHERE rn = 1) AS s
            ON t.FuenteId = @FuenteId AND t.SprintId = s.SprintId
        WHEN MATCHED THEN UPDATE SET Nombre = s.Nombre, Estado = s.Estado, TableroId = s.TableroId, Objetivo = s.Objetivo,
                                     Inicio = s.Inicio, Fin = s.Fin, Completado = s.Completado, Actualizado = SYSDATETIMEOFFSET()
        WHEN NOT MATCHED THEN
            INSERT (FuenteId, SprintId, Nombre, Estado, TableroId, Objetivo, Inicio, Fin, Completado)
            VALUES (@FuenteId, s.SprintId, s.Nombre, s.Estado, s.TableroId, s.Objetivo, s.Inicio, s.Fin, s.Completado);

        DELETE x FROM ops.IssueSprint x JOIN #k k ON k.IssueSk = x.IssueSk;
        INSERT ops.IssueSprint (IssueSk, FuenteId, SprintId)
        SELECT DISTINCT IssueSk, @FuenteId, SprintId FROM #s;
    END;

    /* 5. Usuarios: cualquier objeto con accountId en cualquier campo (incluye campos nuevos) ---- */
    MERGE ops.Usuario AS t
    USING (
        SELECT AccountId, Nombre, TipoCuenta, Activo
        FROM (
            SELECT LEFT(u.accountId, 128) AS AccountId, u.displayName AS Nombre, u.accountType AS TipoCuenta, u.active AS Activo,
                   ROW_NUMBER() OVER (PARTITION BY u.accountId ORDER BY (SELECT NULL)) AS rn
            FROM #k k
            CROSS APPLY OPENJSON(k.Json, '$.fields') f
            CROSS APPLY (
                SELECT f.value AS v WHERE f.type = 5
                UNION ALL
                SELECT a.value FROM OPENJSON(CASE WHEN f.type = 4 THEN f.value END) a WHERE a.type = 5
            ) x
            CROSS APPLY OPENJSON(x.v) WITH (accountId varchar(200), displayName nvarchar(255), accountType varchar(20), active bit) u
            WHERE u.accountId IS NOT NULL
        ) q WHERE rn = 1
    ) AS s ON t.FuenteId = @FuenteId AND t.AccountId = s.AccountId
    WHEN MATCHED THEN UPDATE SET Nombre = ISNULL(s.Nombre, t.Nombre), TipoCuenta = ISNULL(s.TipoCuenta, t.TipoCuenta),
                                 Activo = ISNULL(s.Activo, t.Activo), Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, AccountId, Nombre, TipoCuenta, Activo) VALUES (@FuenteId, s.AccountId, s.Nombre, s.TipoCuenta, s.Activo);

    /* 6. Estados y proyectos vistos en los issues (por si el catálogo aún no llega) ---------- */
    MERGE ops.Estado AS t
    USING (SELECT EstadoId, MAX(Estado) AS Nombre, MAX(CategoriaEstado) AS Categoria FROM #i WHERE EstadoId IS NOT NULL GROUP BY EstadoId) AS s
        ON t.FuenteId = @FuenteId AND t.EstadoId = s.EstadoId
    WHEN MATCHED AND (t.Nombre <> ISNULL(s.Nombre, t.Nombre) OR ISNULL(t.Categoria, '') <> ISNULL(s.Categoria, ISNULL(t.Categoria, ''))) THEN
        UPDATE SET Nombre = ISNULL(s.Nombre, t.Nombre), Categoria = ISNULL(s.Categoria, t.Categoria), Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, EstadoId, Nombre, Categoria) VALUES (@FuenteId, s.EstadoId, ISNULL(s.Nombre, s.EstadoId), s.Categoria);

    INSERT ops.Proyecto (FuenteId, ProyectoId, Clave)
    SELECT @FuenteId, ProyectoId, MAX(ISNULL(ProyectoClave, ProyectoId))
    FROM #i i
    WHERE ProyectoId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM ops.Proyecto p WHERE p.FuenteId = @FuenteId AND p.ProyectoId = i.ProyectoId)
    GROUP BY ProyectoId;
END;
GO
