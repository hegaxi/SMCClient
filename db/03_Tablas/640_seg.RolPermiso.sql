/* Qué puede ejecutar un rol:
     'lectura'  todos los procedimientos api con smc:permiso = lectura (incluidos los que se creen después)
     'admin'    todos los procedimientos api con smc:permiso = admin
     'api.X'    un procedimiento específico (permiso fino)
   Los procedimientos con smc:permiso = usuario los puede ejecutar cualquier usuario activo. */
IF OBJECT_ID('seg.RolPermiso', 'U') IS NULL
CREATE TABLE seg.RolPermiso (
    RolId    int           NOT NULL,
    Permiso  nvarchar(200) NOT NULL,
    CONSTRAINT PK_seg_RolPermiso PRIMARY KEY (RolId, Permiso)
);
GO
