/* El worker toma la solicitud pendiente más antigua (READPAST: varios workers no toman la misma). */
CREATE OR ALTER PROCEDURE sync.Solicitud_Tomar
    @Propietario nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    WITH s AS (
        SELECT TOP (1) * FROM sync.Solicitud WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE Estado = 'pendiente' ORDER BY Fecha
    )
    UPDATE s SET Estado = 'tomada', TomadaEn = SYSDATETIMEOFFSET()
    OUTPUT inserted.SolicitudId, f.Codigo AS Fuente, inserted.Entidad, inserted.Modo, inserted.Parametros
    FROM s LEFT JOIN cfg.Fuente f ON f.FuenteId = s.FuenteId;
END;
GO
