/* Elige el tablero que el usuario ve al entrar (NULL = la página de inicio normal). */
CREATE OR ALTER PROCEDURE api.Tablero_Inicio
    @TableroId     int = NULL,
    @UsuarioActual nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF @TableroId IS NOT NULL AND dash.fn_PuedeVerTablero(@TableroId, @UsuarioId) = 0 THROW 50403, 'No tiene acceso a este tablero.', 1;
    MERGE dash.Preferencia AS t USING (SELECT @UsuarioId AS UsuarioId) AS s ON t.UsuarioId = s.UsuarioId
    WHEN MATCHED THEN UPDATE SET TableroInicioId = @TableroId
    WHEN NOT MATCHED THEN INSERT (UsuarioId, TableroInicioId) VALUES (@UsuarioId, @TableroId);
    SELECT @TableroId AS TableroInicioId;
END;
GO
