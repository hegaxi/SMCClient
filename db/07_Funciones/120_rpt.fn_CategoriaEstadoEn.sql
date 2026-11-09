/* Categoría de estado (new | indeterminate | done) que tenía un issue en un momento, según su historial de estados
   (ops.IssueCambio, CampoId = 'status'):
   - el último cambio hasta ese momento;
   - si el primer cambio es posterior, el estado de origen de ese primer cambio;
   - si el issue no tiene historial de estados, su estado actual.
   Base para "terminado al cierre del sprint", "ya terminado al inicio" y arrastres (el estado ACTUAL no sirve: un issue
   terminado tres sprints después se vería terminado en todos). */
CREATE OR ALTER FUNCTION rpt.fn_CategoriaEstadoEn (@IssueSk bigint, @Momento datetimeoffset(3))
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) COALESCE(e.Categoria, x.CategoriaActual) AS Categoria
    FROM (
        SELECT 1 AS Prioridad, u.FuenteId, u.Hacia AS EstadoId, CAST(NULL AS varchar(20)) AS CategoriaActual
        FROM (SELECT TOP (1) c.FuenteId, c.Hacia FROM ops.IssueCambio c
              WHERE c.IssueSk = @IssueSk AND c.CampoId = 'status' AND c.Fecha <= @Momento
              ORDER BY c.Fecha DESC, c.HistoriaId DESC) u
        UNION ALL
        SELECT 2, p.FuenteId, p.Desde, NULL
        FROM (SELECT TOP (1) c.FuenteId, c.Desde, c.Fecha FROM ops.IssueCambio c
              WHERE c.IssueSk = @IssueSk AND c.CampoId = 'status'
              ORDER BY c.Fecha, c.HistoriaId) p
        WHERE p.Fecha > @Momento
        UNION ALL
        SELECT 3, i.FuenteId, i.EstadoId, i.CategoriaEstado FROM ops.Issue i WHERE i.IssueSk = @IssueSk
    ) x
    LEFT JOIN ops.Estado e ON e.FuenteId = x.FuenteId AND e.EstadoId = x.EstadoId
    ORDER BY x.Prioridad;
GO
