/* LA decisión de autorización. La API la llama en cada petición (con caché de segundos) con el usuario y el
   sello de su sesión, y solo deja ejecutar los procedimientos que devuelve. Reglas:
   - Usuario inexistente, inactivo o con sello distinto (cambió su contraseña o lo desactivaron): @Valido = 0,
     la API cierra la sesión.
   - Debe cambiar su contraseña: @DebeCambiar = 1 y ningún procedimiento.
   - smc:permiso = usuario   -> cualquier usuario activo.
   - smc:permiso = lectura / admin (sin propiedad = admin) -> si alguno de sus roles tiene esa categoría
     o el procedimiento específico ('api.Nombre') en seg.RolPermiso. */
CREATE OR ALTER PROCEDURE seg.Permisos_Usuario
    @Login       nvarchar(100),
    @Sello       uniqueidentifier = NULL,
    @Valido      bit = NULL OUTPUT,
    @DebeCambiar bit = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId int;
    SELECT @UsuarioId = UsuarioId, @DebeCambiar = DebeCambiarContrasena
    FROM seg.Usuario
    WHERE Login = @Login AND Activo = 1 AND (@Sello IS NULL OR SelloSeguridad = @Sello);

    SET @Valido = CASE WHEN @UsuarioId IS NULL THEN 0 ELSE 1 END;
    IF @UsuarioId IS NULL OR @DebeCambiar = 1
    BEGIN
        SELECT CAST(NULL AS sysname) AS Procedimiento WHERE 1 = 0;
        RETURN;
    END;

    SELECT Procedimiento FROM seg.fn_ProcedimientosPermitidos(@UsuarioId) ORDER BY Procedimiento;
END;
GO
