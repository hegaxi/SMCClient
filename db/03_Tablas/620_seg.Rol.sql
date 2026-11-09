/* Roles. Los de sistema (Administrador, Consulta) no se pueden borrar. */
IF OBJECT_ID('seg.Rol', 'U') IS NULL
CREATE TABLE seg.Rol (
    RolId        int IDENTITY(1,1) NOT NULL CONSTRAINT PK_seg_Rol PRIMARY KEY,
    Nombre       nvarchar(100)  NOT NULL CONSTRAINT UQ_seg_Rol_Nombre UNIQUE,
    Descripcion  nvarchar(400)  NULL,
    EsSistema    bit            NOT NULL CONSTRAINT DF_seg_Rol_EsSistema DEFAULT 0,
    EsExterno    bit            NOT NULL CONSTRAINT DF_seg_Rol_EsExterno DEFAULT 0   -- clientes: solo consultas personalizadas, limitadas a su organización
);
GO
