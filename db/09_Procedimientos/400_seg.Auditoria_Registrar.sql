CREATE OR ALTER PROCEDURE seg.Auditoria_Registrar
    @Usuario nvarchar(200),
    @Accion  varchar(60),
    @Objeto  nvarchar(200) = NULL,
    @Antes   nvarchar(max) = NULL,
    @Despues nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT seg.Auditoria (Usuario, Accion, Objeto, Antes, Despues) VALUES (ISNULL(@Usuario, N'(desconocido)'), @Accion, @Objeto, @Antes, @Despues);
END;
GO
