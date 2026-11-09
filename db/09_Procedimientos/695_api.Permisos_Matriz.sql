/* Pantalla "Permisos por opción": qué opción del menú tiene cada rol. Tres resultados:
   1. Roles.  2. Opciones del menú (seg.fn_Opciones), con su categoría.  3. Permisos concedidos (rol, permiso), donde el
   permiso es una categoría completa (lectura / admin / usuario), el código de una opción o api.Nombre.
   Los cambios se hacen con api.Rol_Opcion_Establecer (una casilla) o api.Rol_Guardar (todos los permisos de un rol). */
CREATE OR ALTER PROCEDURE api.Permisos_Matriz
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.Nombre AS Rol, r.Descripcion, r.EsExterno, r.EsSistema,
           (SELECT COUNT(*) FROM seg.UsuarioRol ur JOIN seg.Usuario u ON u.UsuarioId = ur.UsuarioId WHERE ur.RolId = r.RolId AND u.Activo = 1) AS UsuariosActivos
    FROM seg.Rol r
    ORDER BY r.EsSistema DESC, r.EsExterno, r.Nombre;

    SELECT Codigo, Titulo, Descripcion, Categoria, Principal, EsAccion, ExentoSync, Procedimientos
    FROM seg.fn_Opciones()
    ORDER BY Categoria, Titulo;

    SELECT r.Nombre AS Rol, rp.Permiso
    FROM seg.RolPermiso rp
    JOIN seg.Rol r ON r.RolId = rp.RolId
    ORDER BY r.Nombre, rp.Permiso;
END;
GO
