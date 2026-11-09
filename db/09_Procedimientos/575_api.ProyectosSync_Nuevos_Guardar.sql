/* Qué pasa con un proyecto que aparece en Jira: se sincroniza solo (1) o queda desactivado hasta activarlo (0). */
CREATE OR ALTER PROCEDURE api.ProyectosSync_Nuevos_Guardar
    @Sincronizar   bit,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @antes nvarchar(10) = (SELECT Valor FROM cfg.Parametro WHERE Clave = 'ProyectosNuevosSincronizar');
    DECLARE @nuevo nvarchar(10) = CASE WHEN @Sincronizar = 1 THEN N'1' ELSE N'0' END;
    UPDATE cfg.Parametro SET Valor = @nuevo WHERE Clave = 'ProyectosNuevosSincronizar';
    IF @@ROWCOUNT = 0
        INSERT cfg.Parametro (Clave, Valor, Descripcion) VALUES ('ProyectosNuevosSincronizar', @nuevo, N'1 = un proyecto nuevo en Jira se sincroniza solo; 0 = queda desactivado.');
    DECLARE @a nvarchar(max) = (SELECT @antes AS Valor FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            @d nvarchar(max) = (SELECT @nuevo AS Valor FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'proyecto.nuevos', @Objeto = N'ProyectosNuevosSincronizar', @Antes = @a, @Despues = @d;
    SELECT CAST(@Sincronizar AS bit) AS NuevosSeSincronizan;
END;
GO
