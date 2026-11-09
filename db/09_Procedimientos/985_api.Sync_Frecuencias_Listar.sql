/* Configuración de la sincronización por fuente y tipo de dato: cada cuántos minutos se pide a Jira y cuándo se avisa
   que los datos están atrasados. */
CREATE OR ALTER PROCEDURE api.Sync_Frecuencias_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.Codigo AS Fuente, e.Entidad, e.Modo, e.FrecuenciaMin, e.Activa, f.MaxAntiguedadMin,
           (SELECT MAX(x.Fin) FROM sync.Ejecucion x WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad AND x.Estado IN ('ok', 'parcial')) AS UltimaOk
    FROM cfg.EntidadSync e JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId
    WHERE f.Activa = 1
    ORDER BY f.Codigo, e.Orden;
END;
GO
