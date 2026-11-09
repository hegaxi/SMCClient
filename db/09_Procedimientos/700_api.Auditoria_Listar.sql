CREATE OR ALTER PROCEDURE api.Auditoria_Listar
    @Desde   date = NULL,
    @Usuario nvarchar(200) = NULL,
    @Top     int = 200
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) Fecha, Usuario, Accion, Objeto, Antes, Despues
    FROM seg.Auditoria
    WHERE (@Desde IS NULL OR Fecha >= CAST(@Desde AS datetimeoffset(3)))
      AND (@Usuario IS NULL OR Usuario LIKE N'%' + @Usuario + N'%')
    ORDER BY AuditoriaId DESC;
END;
GO
