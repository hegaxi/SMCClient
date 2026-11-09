/* Resumen de la sincronización por fuente (el primer resultado de api.Sync_Estado). Categoría 'sesion': lo puede
   consultar cualquier usuario activo, porque la interfaz lo necesita para la pantalla "Sincronizando..." y el aviso de
   datos atrasados. El detalle por entidad (api.Sync_Estado) es una opción del menú que se concede por rol. */
CREATE OR ALTER PROCEDURE api.Sync_Resumen
AS
BEGIN
    SET NOCOUNT ON;
    EXEC api.Sync_Estado @Detalle = 0;
END;
GO
