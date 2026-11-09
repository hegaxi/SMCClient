/* Épica a la que pertenece un issue: él mismo si es épica, su padre si el padre es épica (tareas e historias), o su
   abuelo (subtareas). Devuelve la clave y un texto "CLAVE · Resumen" para mostrar y filtrar. */
CREATE OR ALTER FUNCTION rpt.fn_EpicaIssue (@FuenteId int, @Clave varchar(50), @PadreClave varchar(50), @Nivel smallint)
RETURNS TABLE
AS
RETURN
    SELECT TOP (1) e.Clave AS EpicaClave, CAST(CONCAT(e.Clave, N' · ', LEFT(e.Resumen, 150)) AS nvarchar(220)) AS Epica
    FROM (SELECT CAST(NULL AS varchar(50)) AS x) _
    OUTER APPLY (SELECT p.Clave, p.PadreClave, p.NivelJerarquia FROM ops.Issue p
                 WHERE @Nivel < 1 AND p.FuenteId = @FuenteId AND p.Clave = @PadreClave AND p.Eliminado = 0) p
    OUTER APPLY (SELECT g.Clave, g.NivelJerarquia FROM ops.Issue g
                 WHERE p.NivelJerarquia < 1 AND g.FuenteId = @FuenteId AND g.Clave = p.PadreClave AND g.Eliminado = 0) g
    JOIN ops.Issue e ON e.FuenteId = @FuenteId AND e.Eliminado = 0
     AND e.Clave = CASE WHEN @Nivel >= 1 THEN @Clave WHEN p.NivelJerarquia >= 1 THEN p.Clave WHEN g.NivelJerarquia >= 1 THEN g.Clave END;
GO
