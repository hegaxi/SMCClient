CREATE OR ALTER PROCEDURE api.Avisos_Listar
    @SoloAbiertos bit = 1,
    @Nivel        varchar(12) = NULL,
    @Top          int = 100
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) v.EventoId, f.Codigo AS Fuente, v.Nivel, v.Codigo, v.Mensaje, v.Datos, v.Fecha, v.Atendido
    FROM sync.Evento v LEFT JOIN cfg.Fuente f ON f.FuenteId = v.FuenteId
    WHERE (@SoloAbiertos = 0 OR v.Atendido = 0) AND (@Nivel IS NULL OR v.Nivel = @Nivel)
    ORDER BY v.Fecha DESC;
END;
GO
