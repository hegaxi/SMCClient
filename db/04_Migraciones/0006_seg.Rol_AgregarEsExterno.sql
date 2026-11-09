/* Roles externos (clientes): solo ven las consultas personalizadas compartidas con ellos, limitadas a los tickets de las
   organizaciones de mesa de ayuda del usuario (seg.UsuarioOrganizacion). */
IF COL_LENGTH('seg.Rol', 'EsExterno') IS NULL
    ALTER TABLE seg.Rol ADD EsExterno bit NOT NULL CONSTRAINT DF_seg_Rol_EsExterno DEFAULT 0;
GO
