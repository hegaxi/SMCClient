/* Elimina una consulta personalizada (quien tiene la opción "Eliminar consulta personalizada"). Los filtros guardados que la usen dejan de funcionar. */
CREATE OR ALTER PROCEDURE api.ConsultaPersonalizada_Eliminar
    @ConsultaId    int,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF NOT EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@u) WHERE Procedimiento = N'ConsultaPersonalizada_Eliminar')
        THROW 50403, 'No tiene permiso para eliminar consultas personalizadas.', 1;
    DECLARE @nombre nvarchar(150) = (SELECT Nombre FROM dash.Consulta WHERE ConsultaId = @ConsultaId);
    IF @nombre IS NULL THROW 50404, 'La consulta no existe.', 1;
    DELETE dash.Consulta WHERE ConsultaId = @ConsultaId;
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'consulta.eliminar', @Objeto = @nombre;
    SELECT @ConsultaId AS ConsultaId;
END;
GO
