/* Tableros que ve el usuario: los suyos, los compartidos con él o con sus roles (y todos, si es administrador). */
CREATE OR ALTER PROCEDURE api.Tableros_Listar
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    SELECT t.TableroId, t.Nombre, t.Descripcion, u.Nombre AS Propietario,
           CAST(CASE WHEN t.PropietarioId = @UsuarioId THEN 1 ELSE 0 END AS bit) AS EsMio,
           (SELECT STRING_AGG(CASE c.Tipo WHEN 'U' THEN cu.Login ELSE N'rol:' + cr.Nombre END, N', ')
            FROM dash.TableroCompartido c
            LEFT JOIN seg.Usuario cu ON c.Tipo = 'U' AND cu.UsuarioId = c.Id
            LEFT JOIN seg.Rol cr ON c.Tipo = 'R' AND cr.RolId = c.Id
            WHERE c.TableroId = t.TableroId) AS CompartidoCon,
           (SELECT COUNT(*) FROM dash.Widget w WHERE w.TableroId = t.TableroId) AS Widgets,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM dash.Preferencia p WHERE p.UsuarioId = @UsuarioId AND p.TableroInicioId = t.TableroId) THEN 1 ELSE 0 END AS bit) AS EsInicio
    FROM dash.Tablero t
    JOIN seg.Usuario u ON u.UsuarioId = t.PropietarioId
    WHERE dash.fn_PuedeVerTablero(t.TableroId, @UsuarioId) = 1
    ORDER BY EsMio DESC, t.Nombre;
END;
GO
