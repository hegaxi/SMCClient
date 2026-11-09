/* Los nombres de estado cambian seguido; la CATEGORÍA (new / indeterminate / done) es estable
   y es la que usan los reportes para decidir si algo está abierto o cerrado. */
IF OBJECT_ID('ops.Estado', 'U') IS NULL
CREATE TABLE ops.Estado (
    FuenteId     int            NOT NULL,
    EstadoId     varchar(30)    NOT NULL,
    Nombre       nvarchar(255)  NOT NULL,
    Categoria    varchar(20)    NULL,          -- new | indeterminate | done
    Actualizado  datetimeoffset(3) NOT NULL CONSTRAINT DF_ops_Estado_Actualizado DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT PK_ops_Estado PRIMARY KEY (FuenteId, EstadoId)
);
GO
