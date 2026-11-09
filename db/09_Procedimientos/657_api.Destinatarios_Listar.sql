/* Usuarios activos y roles con quienes se puede compartir un tablero o una consulta personalizada (lista "Compartir
   con"). Valor: el login o 'rol:Nombre', el formato de @CompartirCon. A un usuario externo (cliente) no se le muestra
   a nadie: los clientes no deben conocer a los usuarios ni los roles internos. */
CREATE OR ALTER PROCEDURE api.Destinatarios_Listar
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual);
    DECLARE @interno bit = CASE WHEN @UsuarioId IS NOT NULL AND seg.fn_EsExterno(@UsuarioId) = 0 THEN 1 ELSE 0 END;

    SELECT x.Valor, x.Etiqueta, x.Tipo
    FROM (
        SELECT N'rol:' + r.Nombre AS Valor, N'Rol ' + r.Nombre AS Etiqueta, N'Todos los usuarios con este rol' AS Tipo, 0 AS Orden
        FROM seg.Rol r
        UNION ALL
        SELECT u.Login, u.Nombre, u.Login, 1
        FROM seg.Usuario u
        WHERE u.Activo = 1 AND u.UsuarioId <> @UsuarioId
    ) x
    WHERE @interno = 1
    ORDER BY x.Orden, x.Etiqueta;
END;
GO
