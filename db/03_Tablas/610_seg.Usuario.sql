/* Usuarios de la aplicación con su contraseña. La contraseña NUNCA llega en claro a la base: la API calcula
   el hash (PBKDF2-SHA256) y aquí solo se guardan hash, sal e iteraciones. Las reglas (longitud mínima,
   bloqueo por intentos, cambio obligatorio, quién puede restablecer) viven en los procedimientos seg.* / api.*. */
IF OBJECT_ID('seg.Usuario', 'U') IS NULL
CREATE TABLE seg.Usuario (
    UsuarioId              int IDENTITY(1,1) NOT NULL CONSTRAINT PK_seg_Usuario PRIMARY KEY,
    Login                  nvarchar(100)  NOT NULL CONSTRAINT UQ_seg_Usuario_Login UNIQUE,
    Nombre                 nvarchar(200)  NOT NULL,
    Activo                 bit            NOT NULL CONSTRAINT DF_seg_Usuario_Activo DEFAULT 1,
    ContrasenaHash         varbinary(64)  NULL,        -- NULL = aún sin contraseña (no puede entrar)
    ContrasenaSal          varbinary(32)  NULL,
    ContrasenaIteraciones  int            NULL,
    ContrasenaFecha        datetimeoffset(3) NULL,
    DebeCambiarContrasena  bit            NOT NULL CONSTRAINT DF_seg_Usuario_DebeCambiar DEFAULT 1,
    IntentosFallidos       int            NOT NULL CONSTRAINT DF_seg_Usuario_Intentos DEFAULT 0,
    BloqueadoHasta         datetimeoffset(3) NULL,
    SelloSeguridad         uniqueidentifier NOT NULL CONSTRAINT DF_seg_Usuario_Sello DEFAULT NEWID(),  -- cambia con la contraseña: invalida sesiones
    FechaAlta              datetimeoffset(3) NOT NULL CONSTRAINT DF_seg_Usuario_FechaAlta DEFAULT SYSDATETIMEOFFSET(),
    UltimoAcceso           datetimeoffset(3) NULL,
    CONSTRAINT CK_seg_Usuario_Login CHECK (LEN(LTRIM(RTRIM(Login))) > 0)
);
GO
