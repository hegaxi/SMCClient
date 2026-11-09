/* Desde esta versión ninguna opción del menú queda abierta a todos: tableros, filtros y consultas personalizadas
   (categoría 'usuario') también se conceden por rol. Para no quitarle nada a nadie, los roles que ya existen reciben la
   categoría 'usuario', que equivale a lo que podían hacer. El administrador puede quitarla en "Permisos por opción". */
IF OBJECT_ID('seg.RolPermiso', 'U') IS NOT NULL AND OBJECT_ID('seg.Rol', 'U') IS NOT NULL
    INSERT seg.RolPermiso (RolId, Permiso)
    SELECT r.RolId, N'usuario'
    FROM seg.Rol r
    WHERE NOT EXISTS (SELECT 1 FROM seg.RolPermiso x WHERE x.RolId = r.RolId AND x.Permiso = N'usuario');
GO
