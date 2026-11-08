/* Ve un tablero: su propietario, a quien se le compartió (directo o por uno de sus roles) y los administradores. */
CREATE OR ALTER FUNCTION dash.fn_PuedeVerTablero (@TableroId int, @UsuarioId int)
RETURNS bit
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM dash.Tablero WHERE TableroId = @TableroId AND PropietarioId = @UsuarioId)
                  OR EXISTS (SELECT 1 FROM dash.TableroCompartido WHERE TableroId = @TableroId AND Tipo = 'U' AND Id = @UsuarioId)
                  OR EXISTS (SELECT 1 FROM dash.TableroCompartido c JOIN seg.UsuarioRol ur ON ur.RolId = c.Id
                             WHERE c.TableroId = @TableroId AND c.Tipo = 'R' AND ur.UsuarioId = @UsuarioId)
                  OR seg.fn_EsAdministrador(@UsuarioId) = 1
                THEN 1 ELSE 0 END;
END;
GO
