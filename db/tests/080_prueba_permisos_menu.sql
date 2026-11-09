/* Toda opción del menú se concede por rol: nada queda abierto a cualquier usuario salvo lo mínimo de la sesión.
   Ejecutar después de 020. Los usuarios y roles que agrega se borran al final. */
SET NOCOUNT ON;
GO
IF SCHEMA_ID('prueba') IS NULL EXEC ('CREATE SCHEMA prueba');
GO
CREATE OR ALTER PROCEDURE prueba.Afirmar @Condicion bit, @Mensaje nvarchar(400)
AS
BEGIN
    IF ISNULL(@Condicion, 0) = 0 BEGIN DECLARE @m nvarchar(500) = N'FALLÓ: ' + @Mensaje; THROW 50999, @m, 1; END;
    PRINT N'ok  ' + @Mensaje;
END;
GO
CREATE OR ALTER PROCEDURE prueba.AfirmarError @Sql nvarchar(max), @Numero int, @Mensaje nvarchar(400)
AS
BEGIN
    DECLARE @n int = 0, @texto nvarchar(4000);
    BEGIN TRY EXEC sp_executesql @Sql; END TRY
    BEGIN CATCH SELECT @n = ERROR_NUMBER(), @texto = ERROR_MESSAGE(); IF @@TRANCOUNT > 0 ROLLBACK; END CATCH;
    DECLARE @ok bit = CASE WHEN @n = @Numero THEN 1 ELSE 0 END;
    DECLARE @m nvarchar(800) = CONCAT(@Mensaje, CASE WHEN @ok = 0 THEN CONCAT(N' (error ', @n, N': ', @texto, N')') ELSE N'' END);
    EXEC prueba.Afirmar @ok, @m;
END;
GO
/* Lista ",A,B," de los procedimientos que puede ejecutar un usuario. */
CREATE OR ALTER FUNCTION prueba.fn_Lista (@Login nvarchar(100))
RETURNS nvarchar(max)
AS
BEGIN
    RETURN N',' + ISNULL((SELECT STRING_AGG(CAST(Procedimiento AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY Procedimiento)
                          FROM seg.fn_ProcedimientosPermitidos((SELECT UsuarioId FROM seg.Usuario WHERE Login = @Login))), N'') + N',';
END;
GO

/* ===== Catálogo de opciones ===== */
DECLARE @ok bit;
SET @ok = CASE WHEN (SELECT STRING_AGG(Procedimiento, ',') WITHIN GROUP (ORDER BY Procedimiento) FROM seg.fn_OpcionProcedimiento() WHERE Categoria = N'sesion')
                    = N'Mi_Usuario,Sync_Resumen' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Solo "quién soy" y el resumen de la sincronización quedan abiertos a todo usuario activo';
SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM seg.fn_OpcionProcedimiento() o
                                WHERE o.Categoria <> N'sesion' AND NOT EXISTS (SELECT 1 FROM seg.fn_Opciones() x WHERE x.Codigo = o.Opcion))
                AND NOT EXISTS (SELECT 1 FROM seg.fn_OpcionProcedimiento() WHERE Categoria NOT IN (N'sesion', N'usuario', N'lectura', N'admin'))
               THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Cada procedimiento del esquema api pertenece a una opción de menú con categoría válida';
SET @ok = CASE WHEN (SELECT Procedimientos FROM seg.fn_Opciones() WHERE Codigo = N'tableros') = N'Tablero_Inicio, Tablero_Obtener, Tableros_Listar'
                AND (SELECT Procedimientos FROM seg.fn_Opciones() WHERE Codigo = N'busqueda_avanzada') = N'Issues_Campos, Issues_Consultar, Issues_Resumir, Issues_Valores'
                AND (SELECT Titulo FROM seg.fn_Opciones() WHERE Codigo = N'api.Horas_PorPersona') = N'Horas por persona (tabla)'
                AND EXISTS (SELECT 1 FROM seg.fn_Opciones() WHERE Codigo = N'contrasena.restablecer' AND Categoria = N'admin')
               THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Las pantallas de varios procedimientos son una sola opción; las demás toman el título de su procedimiento';
GO

/* ===== Un rol sin permisos no ve ninguna opción ===== */
DECLARE @ok bit, @lista nvarchar(max), @sql nvarchar(max);
DECLARE @t TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
DECLARE @r TABLE (Nombre nvarchar(100), Descripcion nvarchar(400), Permisos nvarchar(max), UsuariosActivos int, EsSistema bit);
DECLARE @admin nvarchar(200) = (SELECT TOP (1) u.Login FROM seg.Usuario u WHERE u.Activo = 1 AND seg.fn_EsAdministrador(u.UsuarioId) = 1 ORDER BY u.UsuarioId);
INSERT @r EXEC api.Rol_Guardar @Nombre = N'Vacio80', @Descripcion = N'Sin permisos', @Permisos = N'', @UsuarioActual = @admin;
INSERT @t EXEC api.Usuario_Guardar @Login = N'u80', @Nombre = N'Usuario 80', @Roles = N'Vacio80', @UsuarioActual = @admin;
INSERT @t EXEC api.Usuario_Guardar @Login = N'otro80', @Nombre = N'Otro 80', @Roles = N'Consulta', @UsuarioActual = @admin;
SET @lista = prueba.fn_Lista(N'u80');
SET @ok = CASE WHEN @lista = N',Mi_Usuario,Sync_Resumen,' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Rol sin permisos: ni tableros, ni filtros, ni consultas compartidas, ni estado de la sincronización';

/* ===== Conceder y quitar opciones, casilla por casilla ===== */
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Vacio80', @Permiso = N'tableros', @Concedido = 1, @UsuarioActual = @admin;
SET @lista = prueba.fn_Lista(N'u80');
SET @ok = CASE WHEN @lista LIKE N'%,Tableros_Listar,%' AND @lista LIKE N'%,Tablero_Obtener,%' AND @lista NOT LIKE N'%,Tablero_Guardar,%'
                AND @lista NOT LIKE N'%,Filtros_Listar,%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'"Tableros" deja verlos pero no crearlos ni usar filtros';
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Vacio80', @Permiso = N'tableros.editar', @Concedido = 1, @UsuarioActual = @admin;
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Vacio80', @Permiso = N'busqueda_avanzada', @Concedido = 1, @UsuarioActual = @admin;
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Vacio80', @Permiso = N'api.Horas_PorPersona', @Concedido = 1, @UsuarioActual = @admin;
SET @lista = prueba.fn_Lista(N'u80');
SET @ok = CASE WHEN @lista LIKE N'%,Tablero_Guardar,%' AND @lista LIKE N'%,Widget_Mover,%'
                AND @lista LIKE N'%,Issues_Consultar,%' AND @lista LIKE N'%,Issues_Campos,%' AND @lista LIKE N'%,Issues_Resumir,%'
                AND @lista LIKE N'%,Horas_PorPersona,%' AND @lista NOT LIKE N'%,Issues_Buscar,%' AND @lista NOT LIKE N'%,Sync_Estado,%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Cada opción concedida trae sus procedimientos y nada más';
SET @ok = CASE WHEN (SELECT Permisos FROM @r WHERE Nombre = N'Vacio80') = N'api.Horas_PorPersona, busqueda_avanzada, tableros, tableros.editar' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'La lista de roles muestra las opciones concedidas';
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Vacio80', @Permiso = N'tableros.editar', @Concedido = 0, @UsuarioActual = @admin;
SET @lista = prueba.fn_Lista(N'u80');
SET @ok = CASE WHEN @lista NOT LIKE N'%,Tablero_Guardar,%' AND @lista LIKE N'%,Tableros_Listar,%' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Quitar una opción retira solo sus procedimientos';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM seg.Auditoria WHERE Accion = 'rol.guardar' AND Objeto = N'Vacio80' AND Despues LIKE N'%busqueda_avanzada%') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Cada cambio de permisos queda en la auditoría';
SET @sql = N'EXEC api.Rol_Opcion_Establecer @Rol = N''Vacio80'', @Permiso = N''no.existe'', @Concedido = 1, @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Opción inexistente rechazada';
SET @sql = N'EXEC api.Rol_Opcion_Establecer @Rol = N''Vacio80'', @Permiso = N''api.Mi_Usuario'', @Concedido = 1, @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Lo de la sesión no se concede (ya lo tienen todos)';
SET @sql = N'EXEC api.Rol_Opcion_Establecer @Rol = N''Administrador'', @Permiso = N''admin'', @Concedido = 0, @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50409, N'Al rol Administrador no se le quita la administración';

/* ===== Restablecer contraseña también es una opción ===== */
SET @sql = N'EXEC seg.Contrasena_Establecer @Login = N''otro80'', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12, @UsuarioActual = N''u80'';';
EXEC prueba.AfirmarError @sql, 50403, N'Sin la opción no restablece contraseñas de otros';
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Vacio80', @Permiso = N'contrasena.restablecer', @Concedido = 1, @UsuarioActual = @admin;
DECLARE @sello uniqueidentifier;
EXEC seg.Contrasena_Establecer @Login = N'otro80', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12, @UsuarioActual = N'u80', @SelloNuevo = @sello OUTPUT;
DECLARE @yo TABLE (Login nvarchar(100), Nombre nvarchar(200), Roles nvarchar(400), EsAdministrador bit, PuedeRestablecer bit);
INSERT @yo EXEC api.Mi_Usuario @UsuarioActual = N'u80';
SET @ok = CASE WHEN @sello IS NOT NULL AND (SELECT PuedeRestablecer FROM @yo) = 1 AND (SELECT EsAdministrador FROM @yo) = 0 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Con la opción restablece contraseñas sin ser administrador';
GO

/* ===== Roles externos (clientes) ===== */
DECLARE @ok bit, @lista nvarchar(max), @sql nvarchar(max);
DECLARE @r TABLE (Nombre nvarchar(100), Descripcion nvarchar(400), Permisos nvarchar(max), UsuariosActivos int, EsSistema bit);
DECLARE @t TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
DECLARE @admin nvarchar(200) = (SELECT TOP (1) u.Login FROM seg.Usuario u WHERE u.Activo = 1 AND seg.fn_EsAdministrador(u.UsuarioId) = 1 ORDER BY u.UsuarioId);
SET @ok = CASE WHEN (SELECT STRING_AGG(rp.Permiso, ',') FROM seg.RolPermiso rp JOIN seg.Rol r ON r.RolId = rp.RolId WHERE r.Nombre = N'Cliente') = N'consultas_personalizadas' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'El rol Cliente nace solo con "Consultas personalizadas"';
INSERT @t EXEC api.Usuario_Guardar @Login = N'cli80', @Nombre = N'Cliente 80', @Roles = N'Cliente', @UsuarioActual = @admin;
SET @lista = prueba.fn_Lista(N'cli80');
SET @ok = CASE WHEN @lista LIKE N'%,ConsultaPersonalizada_Ejecutar,%' AND @lista NOT LIKE N'%,Tableros_Listar,%' AND @lista NOT LIKE N'%,Filtros_Listar,%'
                AND @lista NOT LIKE N'%,Sync_Estado,%' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Un cliente ve sus consultas, pero no tableros ni filtros si no se los conceden';
SET @sql = N'EXEC api.Rol_Opcion_Establecer @Rol = N''Cliente'', @Permiso = N''api.Issues_Buscar'', @Concedido = 1, @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'A un rol externo no se le conceden reportes internos';
SET @sql = N'EXEC api.Rol_Opcion_Establecer @Rol = N''Cliente'', @Permiso = N''contrasena.restablecer'', @Concedido = 1, @UsuarioActual = N''' + @admin + N''';';
EXEC prueba.AfirmarError @sql, 50400, N'Ni restablecer contraseñas';
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Cliente', @Permiso = N'filtros', @Concedido = 1, @UsuarioActual = @admin;
SET @lista = prueba.fn_Lista(N'cli80');
SET @ok = CASE WHEN @lista LIKE N'%,Filtros_Listar,%' THEN 1 ELSE 0 END; EXEC prueba.Afirmar @ok, N'Sí se le pueden conceder filtros';
DELETE @r; INSERT @r EXEC api.Rol_Opcion_Establecer @Rol = N'Cliente', @Permiso = N'filtros', @Concedido = 0, @UsuarioActual = @admin;

/* ===== Matriz de permisos ===== */
DECLARE @opciones TABLE (Codigo nvarchar(200), Titulo nvarchar(200), Descripcion nvarchar(400), Categoria nvarchar(50), Principal sysname,
                         EsAccion bit, ExentoSync bit, Procedimientos nvarchar(max));
INSERT @opciones SELECT Codigo, Titulo, Descripcion, Categoria, Principal, EsAccion, ExentoSync, Procedimientos FROM seg.fn_Opciones();
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @opciones) >= 35 AND EXISTS (SELECT 1 FROM @opciones WHERE Codigo = N'api.Permisos_Matriz') THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'La matriz lista todas las opciones del menú, incluida ella misma';
GO

/* ===== Limpieza ===== */
DELETE seg.UsuarioRol WHERE UsuarioId IN (SELECT UsuarioId FROM seg.Usuario WHERE Login IN (N'u80', N'otro80', N'cli80'));
DELETE seg.Usuario WHERE Login IN (N'u80', N'otro80', N'cli80');
DELETE seg.RolPermiso WHERE RolId = (SELECT RolId FROM seg.Rol WHERE Nombre = N'Vacio80');
DELETE seg.Rol WHERE Nombre = N'Vacio80';
GO
DROP FUNCTION prueba.fn_Lista; DROP PROCEDURE prueba.AfirmarError; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DE PERMISOS POR OPCIÓN PASARON';
GO
