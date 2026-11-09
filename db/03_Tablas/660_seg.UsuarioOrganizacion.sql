/* Organizaciones de mesa de ayuda (Jira Service Management) de un usuario externo (cliente): las consultas personalizadas
   que ve se limitan a los tickets de sus organizaciones. Un usuario con un rol externo y sin organización no ve tickets. */
IF OBJECT_ID('seg.UsuarioOrganizacion', 'U') IS NULL
CREATE TABLE seg.UsuarioOrganizacion (
    UsuarioId     int            NOT NULL,
    Organizacion  nvarchar(255)  NOT NULL,
    CONSTRAINT PK_seg_UsuarioOrganizacion PRIMARY KEY (UsuarioId, Organizacion)
);
GO
