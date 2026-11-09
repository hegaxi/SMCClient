/* El worker ya guardó en raw el historial / SLA de estos issues: dejan de estar pendientes.
   Solo se borran los que no se volvieron a encolar después de tomarlos (Agregado <= @TomadoEn). */
CREATE OR ALTER PROCEDURE sync.IssuePendiente_Completar
    @Fuente   varchar(50),
    @Entidad  varchar(40),
    @Ids      sync.IdTipo READONLY,
    @TomadoEn datetimeoffset(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente);
    DELETE t FROM sync.IssuePendiente t
    JOIN @Ids i ON i.IdExterno = t.IssueId
    WHERE t.FuenteId = @FuenteId AND t.Entidad = @Entidad AND t.Agregado <= @TomadoEn;
    SELECT @@ROWCOUNT AS Completados;
END;
GO
