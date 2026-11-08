/* La API informa si la contraseña coincidió y la base decide si el usuario entra:
   ok | invalido | bloqueado | inactivo. Aplica el bloqueo por intentos fallidos (cfg.Parametro
   IntentosFallidosMaximos / MinutosBloqueo) y registra todo en seg.Auditoria. */
CREATE OR ALTER PROCEDURE seg.Login_Resultado
    @Login     nvarchar(100),
    @Coincide  bit,
    @Origen    nvarchar(100) = NULL          -- IP del cliente
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @max int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'IntentosFallidosMaximos') AS int), 5);
    DECLARE @minutos int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'MinutosBloqueo') AS int), 15);
    DECLARE @ahora datetimeoffset(3) = SYSDATETIMEOFFSET();
    DECLARE @UsuarioId int, @activo bit, @bloqueadoHasta datetimeoffset(3), @resultado varchar(12), @datos nvarchar(200);
    SET @datos = (SELECT @Origen AS origen FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    BEGIN TRAN;
    SELECT @UsuarioId = UsuarioId, @activo = Activo, @bloqueadoHasta = BloqueadoHasta
    FROM seg.Usuario WITH (UPDLOCK, HOLDLOCK) WHERE Login = @Login;

    IF @UsuarioId IS NULL
        SET @resultado = 'invalido';
    ELSE IF @bloqueadoHasta > @ahora
        SET @resultado = 'bloqueado';
    ELSE IF @Coincide = 0
    BEGIN
        UPDATE seg.Usuario
        SET IntentosFallidos = CASE WHEN IntentosFallidos + 1 >= @max THEN 0 ELSE IntentosFallidos + 1 END,
            BloqueadoHasta = CASE WHEN IntentosFallidos + 1 >= @max THEN DATEADD(MINUTE, @minutos, @ahora) ELSE BloqueadoHasta END
        WHERE UsuarioId = @UsuarioId;
        SET @resultado = CASE WHEN (SELECT BloqueadoHasta FROM seg.Usuario WHERE UsuarioId = @UsuarioId) > @ahora THEN 'bloqueado' ELSE 'invalido' END;
        IF @resultado = 'bloqueado'
            EXEC seg.Auditoria_Registrar @Usuario = N'(sistema)', @Accion = 'sesion.bloqueo', @Objeto = @Login, @Despues = @datos;
    END
    ELSE IF @activo = 0
        SET @resultado = 'inactivo';
    ELSE
    BEGIN
        UPDATE seg.Usuario SET IntentosFallidos = 0, BloqueadoHasta = NULL, UltimoAcceso = @ahora WHERE UsuarioId = @UsuarioId;
        SET @resultado = 'ok';
    END;

    DECLARE @accion varchar(60) = CASE WHEN @resultado = 'ok' THEN 'sesion.inicio' ELSE 'sesion.fallida' END;
    DECLARE @quien nvarchar(200) = CASE WHEN @UsuarioId IS NULL THEN N'(desconocido)' ELSE @Login END;
    DECLARE @obj nvarchar(200) = CASE WHEN @resultado = 'ok' THEN NULL ELSE @resultado END;
    EXEC seg.Auditoria_Registrar @Usuario = @quien, @Accion = @accion, @Objeto = @obj, @Despues = @datos;
    COMMIT;

    SELECT @resultado AS Resultado, u.Nombre, u.SelloSeguridad, u.DebeCambiarContrasena
    FROM (SELECT 1 AS x) d LEFT JOIN seg.Usuario u ON u.UsuarioId = @UsuarioId AND @resultado = 'ok';
END;
GO
