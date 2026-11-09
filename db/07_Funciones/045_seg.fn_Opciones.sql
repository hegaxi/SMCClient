/* Catálogo de opciones de menú que se conceden a los roles (pantalla "Permisos por opción" y validación de
   api.Rol_Guardar). Salen de los procedimientos del esquema api, así que un procedimiento nuevo aparece solo:
   - las pantallas de varios procedimientos (smc:opcion) se nombran aquí;
   - las demás opciones toman el título y la descripción de su procedimiento;
   - 'contrasena.restablecer' no es un procedimiento: la API calcula el hash y seg.Contrasena_Establecer la revisa.
   Principal: procedimiento que representa la opción (la interfaz la ubica en el menú por su nombre). */
CREATE OR ALTER FUNCTION seg.fn_Opciones ()
RETURNS TABLE
AS
RETURN
    WITH grupo AS (
        SELECT * FROM (VALUES
            (N'tableros',                 N'Tableros',                  N'Ver los tableros propios y compartidos, y elegir el de inicio.',                       N'Tableros_Listar'),
            (N'tableros.editar',          N'Crear y editar tableros',   N'Nuevo tablero: widgets, orden y con quién se comparte.',                               N'Tablero_Guardar'),
            (N'filtros',                  N'Mis filtros',               N'Guardar las consultas como filtros, compartirlos y usarlos en tableros.',              N'Filtros_Listar'),
            (N'busqueda_avanzada',        N'Búsqueda avanzada',         N'Filtros desde cero sobre cualquier campo de Jira, con columnas, orden y resúmenes.',   N'Issues_Consultar'),
            (N'consultas_personalizadas', N'Consultas personalizadas',  N'Ver y ejecutar las consultas personalizadas compartidas con el usuario o su rol.',     N'ConsultasPersonalizadas_Listar')
        ) v (Codigo, Titulo, Descripcion, Principal)),
    opcion AS (
        SELECT o.Opcion, MAX(o.Categoria) AS Categoria, MIN(o.Procedimiento) AS Primero,
               STRING_AGG(CAST(o.Procedimiento AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY o.Procedimiento) AS Procedimientos
        FROM seg.fn_OpcionProcedimiento() o
        WHERE o.Categoria <> N'sesion'
        GROUP BY o.Opcion)
    SELECT o.Opcion AS Codigo,
           COALESCE(g.Titulo, CAST(t.Titulo AS nvarchar(200)), p.Principal) AS Titulo,
           COALESCE(g.Descripcion, CAST(t.Descripcion AS nvarchar(400))) AS Descripcion,
           o.Categoria, p.Principal,
           CAST(CASE WHEN g.Codigo IS NULL AND CAST(t.Accion AS nvarchar(5)) = N'1' THEN 1 ELSE 0 END AS bit) AS EsAccion,
           CAST(CASE WHEN CAST(t.Exento AS nvarchar(5)) = N'1' THEN 1 ELSE 0 END AS bit) AS ExentoSync,
           o.Procedimientos,
           CAST(0 AS bit) AS SinProcedimiento
    FROM opcion o
    LEFT JOIN grupo g ON g.Codigo = o.Opcion
    CROSS APPLY (SELECT COALESCE(g.Principal, o.Primero) AS Principal) p
    CROSS APPLY (SELECT OBJECT_ID(N'api.' + p.Principal) AS Id) ob
    CROSS APPLY (SELECT (SELECT e.value FROM sys.extended_properties e WHERE e.class = 1 AND e.major_id = ob.Id AND e.minor_id = 0 AND e.name = 'smc:titulo') AS Titulo,
                        (SELECT e.value FROM sys.extended_properties e WHERE e.class = 1 AND e.major_id = ob.Id AND e.minor_id = 0 AND e.name = 'MS_Description') AS Descripcion,
                        (SELECT e.value FROM sys.extended_properties e WHERE e.class = 1 AND e.major_id = ob.Id AND e.minor_id = 0 AND e.name = 'smc:accion') AS Accion,
                        (SELECT e.value FROM sys.extended_properties e WHERE e.class = 1 AND e.major_id = ob.Id AND e.minor_id = 0 AND e.name = 'smc:exentoSync') AS Exento) t
    UNION ALL
    SELECT N'contrasena.restablecer', N'Restablecer contraseña', N'Asigna una contraseña temporal a otro usuario; deberá cambiarla al entrar.',
           N'admin', N'Usuario_RestablecerContrasena', CAST(1 AS bit), CAST(1 AS bit), NULL, CAST(1 AS bit);
GO
