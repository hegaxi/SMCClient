/* Cada procedimiento del esquema api con su categoría y la opción de menú a la que pertenece:
   - Categoria (smc:permiso): lectura | admin | usuario (funciones personales: tableros, filtros, consultas compartidas)
     | sesion (lo mínimo para usar la aplicación: quién soy y el resumen de la sincronización; lo tiene todo usuario activo).
     Sin propiedad = admin.
   - Opcion (smc:opcion): las pantallas que usan varios procedimientos los agrupan en una sola opción (p. ej. 'tableros');
     sin propiedad, cada procedimiento es su propia opción: 'api.Nombre'.
   Un rol recibe opciones o categorías completas en seg.RolPermiso. */
CREATE OR ALTER FUNCTION seg.fn_OpcionProcedimiento ()
RETURNS TABLE
AS
RETURN
    SELECT p.name AS Procedimiento, p.object_id AS ObjetoId,
           ISNULL(x.Categoria, N'admin') AS Categoria,
           ISNULL(x.Opcion, N'api.' + p.name) AS Opcion
    FROM sys.procedures p
    CROSS APPLY (SELECT (SELECT CAST(e.value AS nvarchar(200)) FROM sys.extended_properties e
                         WHERE e.class = 1 AND e.major_id = p.object_id AND e.minor_id = 0 AND e.name = 'smc:permiso') AS Categoria,
                        (SELECT CAST(e.value AS nvarchar(200)) FROM sys.extended_properties e
                         WHERE e.class = 1 AND e.major_id = p.object_id AND e.minor_id = 0 AND e.name = 'smc:opcion') AS Opcion) x
    WHERE p.schema_id = SCHEMA_ID('api');
GO
