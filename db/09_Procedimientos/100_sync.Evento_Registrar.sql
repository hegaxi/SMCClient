/* Registra un aviso. Si ya hay uno igual sin atender (mismo código y datos), no lo duplica:
   así un rol sin campo no genera un aviso nuevo cada 15 minutos. */
CREATE OR ALTER PROCEDURE sync.Evento_Registrar
    @FuenteId    int = NULL,
    @EjecucionId bigint = NULL,
    @Nivel       varchar(12),
    @Codigo      varchar(60),
    @Mensaje     nvarchar(1000),
    @Datos       nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM sync.Evento
               WHERE Atendido = 0 AND Codigo = @Codigo
                 AND ISNULL(FuenteId, -1) = ISNULL(@FuenteId, -1)
                 AND ISNULL(Datos, N'') = ISNULL(@Datos, N''))
        RETURN;
    INSERT sync.Evento (FuenteId, EjecucionId, Nivel, Codigo, Mensaje, Datos)
    VALUES (@FuenteId, @EjecucionId, @Nivel, @Codigo, @Mensaje, @Datos);
END;
GO
