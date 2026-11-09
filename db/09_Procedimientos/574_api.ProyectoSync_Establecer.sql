/* Activa o desactiva la sincronización de un proyecto. Desactivado: deja de pedirse a Jira y sus datos se ocultan de
   los reportes (no se borran). Al volver a activarlo se piden de nuevo todos sus issues (backfill). Queda auditado. */
CREATE OR ALTER PROCEDURE api.ProyectoSync_Establecer
    @Fuente        varchar(50),
    @Proyecto      varchar(50),
    @Sincronizar   bit,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    IF @FuenteId IS NULL THROW 50404, 'La fuente no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM ops.Proyecto WHERE FuenteId = @FuenteId AND Clave = @Proyecto)
        THROW 50404, 'El proyecto no existe en Jira (o aún no se sincroniza el catálogo de proyectos).', 1;

    DECLARE @antes bit = CASE WHEN EXISTS (SELECT 1 FROM cfg.ProyectoExcluido WHERE FuenteId = @FuenteId AND ProyectoClave = @Proyecto) THEN 0 ELSE 1 END;
    IF @antes <> @Sincronizar
    BEGIN
        BEGIN TRAN;
        DECLARE @motivo nvarchar(200) = N'Desactivado por ' + @UsuarioActual;
        DECLARE @excluir bit = CASE WHEN @Sincronizar = 1 THEN 0 ELSE 1 END;
        EXEC sync.Proyecto_Excluir @Fuente = @Fuente, @Clave = @Proyecto, @Motivo = @motivo, @Excluir = @excluir;
        DECLARE @a nvarchar(max) = (SELECT @antes AS Sincronizar FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                @d nvarchar(max) = (SELECT @Sincronizar AS Sincronizar FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                @obj nvarchar(200) = @Fuente + N'/' + @Proyecto;
        EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'proyecto.sincronizar', @Objeto = @obj, @Antes = @a, @Despues = @d;
        COMMIT;
    END;

    EXEC api.ProyectosSync_Listar @Fuente = @Fuente;
END;
GO
