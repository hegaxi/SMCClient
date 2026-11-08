/* Worklogs (POST /rest/api/3/worklog/list con los ids de /worklog/updated). Contrato: un documento
   por worklog, IdExterno = id del worklog. No depende de que el issue ya exista. */
CREATE OR ALTER PROCEDURE sync.Procesar_Worklogs
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT w.*
    INTO #w
    FROM #lote l
    JOIN raw.Documento d ON d.DocumentoId = l.DocumentoId
    CROSS APPLY OPENJSON(d.Json) WITH (
        WorklogId varchar(30) '$.id', IssueId varchar(30) '$.issueId',
        AutorId varchar(200) '$.author.accountId', AutorNombre nvarchar(255) '$.author.displayName', AutorTipo varchar(20) '$.author.accountType',
        ActualizadoPorId varchar(200) '$.updateAuthor.accountId', ActualizadoPorNombre nvarchar(255) '$.updateAuthor.displayName', ActualizadoPorTipo varchar(20) '$.updateAuthor.accountType',
        Inicio nvarchar(60) '$.started', Segundos int '$.timeSpentSeconds', Creado nvarchar(60) '$.created', Actualizado nvarchar(60) '$.updated') w;

    IF EXISTS (SELECT 1 FROM #w WHERE WorklogId IS NULL OR IssueId IS NULL OR sync.fn_FechaJira(Inicio) IS NULL OR Segundos IS NULL)
        THROW 50050, 'Worklog sin id, issueId, started o timeSpentSeconds.', 1;

    MERGE ops.Worklog AS t
    USING #w AS s ON t.FuenteId = @FuenteId AND t.WorklogId = s.WorklogId
    WHEN MATCHED THEN UPDATE SET IssueId = s.IssueId, AutorId = LEFT(s.AutorId, 128), ActualizadoPorId = LEFT(s.ActualizadoPorId, 128),
        Inicio = sync.fn_FechaJira(s.Inicio), Segundos = s.Segundos, Creado = sync.fn_FechaJira(s.Creado),
        Actualizado = sync.fn_FechaJira(s.Actualizado), Eliminado = 0
    WHEN NOT MATCHED THEN INSERT (FuenteId, WorklogId, IssueId, AutorId, ActualizadoPorId, Inicio, Segundos, Creado, Actualizado)
        VALUES (@FuenteId, s.WorklogId, s.IssueId, LEFT(s.AutorId, 128), LEFT(s.ActualizadoPorId, 128), sync.fn_FechaJira(s.Inicio),
                s.Segundos, sync.fn_FechaJira(s.Creado), sync.fn_FechaJira(s.Actualizado));

    MERGE ops.Usuario AS t
    USING (
        SELECT AccountId, Nombre, TipoCuenta FROM (
            SELECT LEFT(AccountId, 128) AS AccountId, Nombre, TipoCuenta, ROW_NUMBER() OVER (PARTITION BY AccountId ORDER BY (SELECT NULL)) AS rn
            FROM (SELECT AutorId, AutorNombre, AutorTipo FROM #w UNION ALL SELECT ActualizadoPorId, ActualizadoPorNombre, ActualizadoPorTipo FROM #w) u (AccountId, Nombre, TipoCuenta)
            WHERE AccountId IS NOT NULL) q WHERE rn = 1
    ) AS s ON t.FuenteId = @FuenteId AND t.AccountId = s.AccountId
    WHEN MATCHED THEN UPDATE SET Nombre = ISNULL(s.Nombre, t.Nombre), TipoCuenta = ISNULL(s.TipoCuenta, t.TipoCuenta), Actualizado = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, AccountId, Nombre, TipoCuenta) VALUES (@FuenteId, s.AccountId, s.Nombre, s.TipoCuenta);
END;
GO
