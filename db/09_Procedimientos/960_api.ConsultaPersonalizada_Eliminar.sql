/* Elimina una consulta personalizada (solo administradores). Los filtros guardados que la usen dejan de funcionar. */
CREATE OR ALTER PROCEDURE api.ConsultaPersonalizada_Eliminar
    @ConsultaId    int,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF seg.fn_EsAdministrador(@u) = 0 THROW 50403, 'Solo un administrador elimina consultas personalizadas.', 1;
    DECLARE @nombre nvarchar(150) = (SELECT Nombre FROM dash.Consulta WHERE ConsultaId = @ConsultaId);
    IF @nombre IS NULL THROW 50404, 'La consulta no existe.', 1;
    DELETE dash.Consulta WHERE ConsultaId = @ConsultaId;
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'consulta.eliminar', @Objeto = @nombre;
    SELECT @ConsultaId AS ConsultaId;
END;
GO
