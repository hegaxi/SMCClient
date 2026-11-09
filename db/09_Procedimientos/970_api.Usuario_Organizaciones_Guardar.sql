/* Organizaciones de mesa de ayuda de un usuario externo (cliente), separadas por "|" (los nombres pueden llevar comas):
   sus consultas personalizadas se limitan a los tickets de esas organizaciones. Vacío = sin organización (no ve tickets). */
CREATE OR ALTER PROCEDURE api.Usuario_Organizaciones_Guardar
    @Login          nvarchar(100),
    @Organizaciones nvarchar(2000) = NULL,
    @UsuarioActual  nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @Login);
    IF @u IS NULL THROW 50404, 'El usuario no existe.', 1;
    DECLARE @antes nvarchar(max) = (SELECT STRING_AGG(Organizacion, N'|') FROM seg.UsuarioOrganizacion WHERE UsuarioId = @u);
    BEGIN TRAN;
    DELETE seg.UsuarioOrganizacion WHERE UsuarioId = @u;
    INSERT seg.UsuarioOrganizacion (UsuarioId, Organizacion)
    SELECT DISTINCT @u, LEFT(LTRIM(RTRIM(value)), 255) FROM STRING_SPLIT(ISNULL(@Organizaciones, N''), '|') WHERE LTRIM(RTRIM(value)) <> N'';
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'usuario.organizaciones', @Objeto = @Login, @Antes = @antes, @Despues = @Organizaciones;
    COMMIT;
    EXEC api.Usuarios_Externos_Listar;
END;
GO
