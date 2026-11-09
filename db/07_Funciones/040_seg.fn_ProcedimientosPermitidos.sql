/* Procedimientos del esquema api que puede ejecutar un usuario activo (sin revisar sello ni cambio de contraseña).
   TODA opción del menú se concede por rol (seg.RolPermiso); nada queda abierto a cualquier usuario salvo la categoría
   'sesion' (quién soy y el resumen de la sincronización, sin los que la aplicación no abre). Un rol puede tener:
     - una categoría completa: 'lectura', 'admin' o 'usuario' (incluye los procedimientos que se creen después);
     - una opción de menú: su código (p. ej. 'tableros', 'api.Horas_PorPersona'), ver seg.fn_Opciones;
     - un procedimiento específico: 'api.Nombre' (compatibilidad; para un procedimiento suelto es lo mismo que su opción).
   Un usuario con un rol EXTERNO (cliente) solo ejecuta procedimientos de la categoría 'usuario' que tenga concedidos,
   aunque alguno de sus roles tenga más: así un error de configuración no le abre los reportes internos.
   La usan seg.Permisos_Usuario y las reglas de filtros, tableros y consultas personalizadas. */
CREATE OR ALTER FUNCTION seg.fn_ProcedimientosPermitidos (@UsuarioId int)
RETURNS TABLE
AS
RETURN
    SELECT o.Procedimiento
    FROM seg.fn_OpcionProcedimiento() o
    WHERE EXISTS (SELECT 1 FROM seg.Usuario u WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1)
      AND (o.Categoria = N'sesion'
           OR (EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.RolPermiso rp ON rp.RolId = ur.RolId
                       WHERE ur.UsuarioId = @UsuarioId AND rp.Permiso IN (o.Categoria, o.Opcion, N'api.' + o.Procedimiento))
               AND (o.Categoria = N'usuario'
                    OR NOT EXISTS (SELECT 1 FROM seg.UsuarioRol ur JOIN seg.Rol r ON r.RolId = ur.RolId
                                   WHERE ur.UsuarioId = @UsuarioId AND r.EsExterno = 1))));
GO
