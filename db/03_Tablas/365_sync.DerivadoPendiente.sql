/* Recálculos de datos derivados (sync.Derivados_Actualizar) que fallaron. Procesar_Pendientes guarda aquí desde cuándo
   quedó pendiente cada fuente y entidad; en la pasada siguiente recalcula desde esa fecha (no solo lo de la pasada) y
   borra la fila cuando termina bien. Sin esto, los issues de una pasada fallida quedaban con totales viejos. */
IF OBJECT_ID('sync.DerivadoPendiente', 'U') IS NULL
CREATE TABLE sync.DerivadoPendiente (
    FuenteId  int               NOT NULL,
    Entidad   varchar(40)       NOT NULL,
    Desde     datetimeoffset(3) NOT NULL,      -- inicio de la primera pasada cuyo recálculo falló
    Intentos  int               NOT NULL CONSTRAINT DF_sync_DerivadoPendiente_Intentos DEFAULT 1,
    UltimoError nvarchar(2000)  NULL,
    CONSTRAINT PK_sync_DerivadoPendiente PRIMARY KEY (FuenteId, Entidad)
);
GO
