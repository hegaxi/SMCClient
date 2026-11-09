/* Organizaciones de mesa de ayuda que aparecen en los tickets (campo Organizations de JSM), con cuántos tickets tiene
   cada una: para asignarlas a los usuarios externos con el nombre exacto. */
CREATE OR ALTER PROCEDURE api.Organizaciones_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.ValorTexto AS Organizacion, COUNT(DISTINCT v.IssueSk) AS Tickets
    FROM ops.IssueCampoValor v
    JOIN ops.Issue i ON i.IssueSk = v.IssueSk AND i.Eliminado = 0
    JOIN cfg.MapeoCampo m ON m.FuenteId = i.FuenteId AND m.Rol = 'organizacion' AND m.CampoId = v.CampoId
    WHERE v.ValorTexto IS NOT NULL
    GROUP BY v.ValorTexto
    ORDER BY Tickets DESC, Organizacion;
END;
GO
