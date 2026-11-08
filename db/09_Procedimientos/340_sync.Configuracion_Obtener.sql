/* Todo lo que el worker necesita para una fuente, en una llamada:
   1) datos de la fuente, 2) entidades con su última ejecución correcta, 3) proyectos excluidos,
   4) proyectos vigentes no excluidos (para la conciliación de borrados). */
CREATE OR ALTER PROCEDURE sync.Configuracion_Obtener
    @Fuente varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FuenteId int = (SELECT FuenteId FROM cfg.Fuente WHERE Codigo = @Fuente AND Activa = 1);
    IF @FuenteId IS NULL THROW 50011, 'La fuente no existe o está inactiva.', 1;

    SELECT f.FuenteId, f.Codigo, f.Tipo, f.UrlBase, f.CloudId,
           (SELECT MAX(Fin) FROM sync.Ejecucion WHERE FuenteId = f.FuenteId AND Modo = 'conciliacion' AND Estado IN ('ok', 'parcial')) AS UltimaConciliacion,
           (SELECT MAX(Inicio) FROM sync.Ejecucion WHERE FuenteId = f.FuenteId AND Modo = 'conciliacion') AS UltimoIntentoConciliacion
    FROM cfg.Fuente f WHERE f.FuenteId = @FuenteId;

    SELECT e.Entidad, e.Orden, e.Modo, e.FrecuenciaMin, e.Endpoint, e.TamanoLote, e.Parametros,
           (SELECT MAX(x.Fin) FROM sync.Ejecucion x WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad
              AND x.Estado IN ('ok', 'parcial') AND x.Modo IN ('inicial', 'incremental', 'catalogo')) AS UltimaOk,
           u.Inicio AS UltimoIntento, u.Estado AS UltimoEstado
    FROM cfg.EntidadSync e
    OUTER APPLY (SELECT TOP (1) x.Inicio, x.Estado FROM sync.Ejecucion x
                 WHERE x.FuenteId = e.FuenteId AND x.Entidad = e.Entidad AND x.Modo IN ('inicial', 'incremental', 'catalogo')
                 ORDER BY x.EjecucionId DESC) u
    WHERE e.FuenteId = @FuenteId AND e.Activa = 1
    ORDER BY e.Orden;

    SELECT ProyectoClave FROM cfg.ProyectoExcluido WHERE FuenteId = @FuenteId ORDER BY ProyectoClave;

    SELECT p.ProyectoId, p.Clave, p.TipoProyecto
    FROM ops.Proyecto p
    WHERE p.FuenteId = @FuenteId AND p.Eliminado = 0
      AND NOT EXISTS (SELECT 1 FROM cfg.ProyectoExcluido x WHERE x.FuenteId = p.FuenteId AND x.ProyectoClave = p.Clave)
    ORDER BY p.Clave;
END;
GO
