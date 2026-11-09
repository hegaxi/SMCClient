/* Texto para la fila Total de un reporte de horas que no encontró tiempo en el periodo pedido: dice entre qué fechas
   SÍ hay registros, para que quede claro que no faltan datos (p. ej. un proyecto que ya cerró).
     "Sin tiempo en este periodo. SMC25 tiene registros del 02/07/2025 al 05/02/2026"
   @Proyectos: claves separadas por '|' (o una sola); @Personas: nombres o partes de nombre separados por '|'.
   Sin filtros: la fecha del último registro. No cuenta las copias de Automation for Jira (como los reportes).
   Solo se llama cuando el reporte quedó vacío, así que la consulta extra no pesa en el caso normal. */
CREATE OR ALTER FUNCTION rpt.fn_AvisoSinTiempo (@Proyectos nvarchar(1000), @Personas nvarchar(2000))
RETURNS nvarchar(400)
AS
BEGIN
    DECLARE @p TABLE (Clave varchar(50) PRIMARY KEY);
    INSERT @p SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Proyectos, '|') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @g TABLE (Nombre nvarchar(255) PRIMARY KEY);
    INSERT @g SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Personas, '|') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @hayP bit = CASE WHEN EXISTS (SELECT 1 FROM @p) THEN 1 ELSE 0 END,
            @hayG bit = CASE WHEN EXISTS (SELECT 1 FROM @g) THEN 1 ELSE 0 END;
    DECLARE @r nvarchar(400);

    IF @hayP = 1
        -- Por proyecto (hasta 4; si son más, "…"): su rango de registros, o "sin registros".
        SELECT @r = STRING_AGG(CAST(x.Texto AS nvarchar(max)), N'; ') WITHIN GROUP (ORDER BY x.Clave)
        FROM (SELECT TOP (4) p.Clave,
                     CASE WHEN r.Primero IS NULL THEN CONCAT(p.Clave, N' no tiene registros', CASE WHEN @hayG = 1 THEN N' de esa persona' END)
                          ELSE CONCAT(p.Clave, N' tiene registros', CASE WHEN @hayG = 1 THEN N' de esa persona' END, N' del ',
                                      CONVERT(nvarchar(10), r.Primero, 103), N' al ', CONVERT(nvarchar(10), r.Ultimo, 103)) END AS Texto
              FROM @p p
              OUTER APPLY (SELECT MIN(w.Fecha) AS Primero, MAX(w.Fecha) AS Ultimo FROM rpt.vWorklog w
                           WHERE w.ProyectoClave = p.Clave AND w.Origen <> 'copia'
                             AND (@hayG = 0 OR EXISTS (SELECT 1 FROM @g g WHERE w.AtribuidoA LIKE N'%' + g.Nombre + N'%'))) r
              ORDER BY p.Clave) x;
    ELSE
        SELECT @r = CASE WHEN MAX(w.Fecha) IS NULL THEN CASE WHEN @hayG = 1 THEN N'esa persona no tiene registros' ELSE N'no hay registros' END
                         WHEN @hayG = 1 THEN CONCAT(N'esa persona tiene registros del ', CONVERT(nvarchar(10), MIN(w.Fecha), 103), N' al ', CONVERT(nvarchar(10), MAX(w.Fecha), 103))
                         ELSE CONCAT(N'último registro: ', CONVERT(nvarchar(10), MAX(w.Fecha), 103)) END
        FROM rpt.vWorklog w
        WHERE w.Origen <> 'copia' AND (@hayG = 0 OR EXISTS (SELECT 1 FROM @g g WHERE w.AtribuidoA LIKE N'%' + g.Nombre + N'%'));

    RETURN CONCAT(N'Sin tiempo en este periodo. ', UPPER(LEFT(@r, 1)), SUBSTRING(@r, 2, 400),
                  CASE WHEN (SELECT COUNT(*) FROM @p) > 4 THEN N'; …' END);
END;
GO
