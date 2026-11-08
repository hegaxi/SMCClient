CREATE OR ALTER PROCEDURE sync.Candado_Liberar
    @Fuente      varchar(50),
    @Propietario nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE c SET ExpiraEn = DATEADD(SECOND, -1, SYSDATETIMEOFFSET()), Propietario = NULL
    FROM sync.Candado c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId
    WHERE f.Codigo = @Fuente AND c.Propietario = @Propietario;
END;
GO
