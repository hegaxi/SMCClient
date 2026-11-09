/* Lista para elegir un sprint (campos "Sprint" de las consultas). Valor = nombre del sprint (las consultas lo buscan
   por nombre); el detalle dice de qué proyecto es, su estado y sus fechas, porque hay nombres repetidos entre
   proyectos ("Sprint 5"). Con @Proyecto solo los sprints de ese proyecto. Primero los activos, luego los más recientes. */
CREATE OR ALTER PROCEDURE api.Sprints_Listar
    @Proyecto varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.Nombre AS Valor, s.Nombre AS Etiqueta,
           CONCAT(STRING_AGG(CAST(p.ProyectoClave AS nvarchar(50)), N', '), N' · ',
                  CASE s.Estado WHEN 'active' THEN N'activo' WHEN 'closed' THEN N'cerrado' WHEN 'future' THEN N'futuro' ELSE s.Estado END,
                  N' · ', FORMAT(s.Inicio, 'dd/MM/yy'), N'–', FORMAT(s.Fin, 'dd/MM/yy')) AS Detalle
    FROM ops.Sprint s
    CROSS APPLY (SELECT DISTINCT i.ProyectoClave FROM ops.IssueSprint x JOIN rpt.vIssue i ON i.IssueSk = x.IssueSk
                 WHERE x.FuenteId = s.FuenteId AND x.SprintId = s.SprintId) p
    -- @Proyecto: una clave o varias separadas por '|' (campos de varios proyectos, como Tiempos invertidos).
    WHERE @Proyecto IS NULL OR p.ProyectoClave IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Proyecto, '|'))
    GROUP BY s.SprintId, s.Nombre, s.Estado, s.Inicio, s.Fin
    ORDER BY CASE s.Estado WHEN 'active' THEN 0 WHEN 'future' THEN 1 ELSE 2 END, s.Inicio DESC;
END;
GO
