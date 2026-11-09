/* Filtros guardados y tableros: fechas relativas, permisos, compartir y reglas de propiedad.
   Ejecutar sobre una base recién desplegada:  sqlcmd -b -I -x -d SMCClient -i tests/030_prueba_tableros.sql */
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

/* ===== Fechas relativas (hoy = domingo 8 de noviembre de 2026) ===== */
DECLARE @ok bit, @hoy date = '2026-11-08';
SET @ok = CASE WHEN dash.fn_FechaRelativa(N'{hoy}', @hoy) = '2026-11-08' AND dash.fn_FechaRelativa(N'{hoy-30}', @hoy) = '2026-10-09'
                AND dash.fn_FechaRelativa(N'{hoy+7}', @hoy) = '2026-11-15' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'{hoy}, {hoy-30}, {hoy+7}';
SET @ok = CASE WHEN dash.fn_FechaRelativa(N'{inicio_mes}', @hoy) = '2026-11-01' AND dash.fn_FechaRelativa(N'{inicio_mes_anterior}', @hoy) = '2026-10-01'
                AND dash.fn_FechaRelativa(N'{fin_mes_anterior}', @hoy) = '2026-10-31' AND dash.fn_FechaRelativa(N'{inicio_anio}', @hoy) = '2026-01-01'
                AND dash.fn_FechaRelativa(N'{inicio_semana}', @hoy) = '2026-11-02' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Inicio de semana (lunes), de mes, del mes anterior, fin del mes anterior y del año';
SET @ok = CASE WHEN dash.fn_FechaRelativa(N'MDA', @hoy) IS NULL AND dash.fn_FechaRelativa(N'{otra}', @hoy) IS NULL THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Texto normal o llaves desconocidas no son fechas';
SET @ok = CASE WHEN dash.fn_ResolverParametros(N'{"Desde":"{inicio_mes}","Proyecto":"MDA","Pagina":2,"Nota":"a \"b\""}', @hoy)
                    = N'{"Desde":"2026-11-01","Proyecto":"MDA","Pagina":2,"Nota":"a \"b\""}' THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Resuelve las fechas relativas y conserva los demás valores (con comillas escapadas)';
GO

/* ===== Usuarios de la prueba ===== */
DECLARE @t TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
DECLARE @r TABLE (a nvarchar(100), b nvarchar(400), c nvarchar(2000), d int, e bit);
EXEC seg.Instalacion_CrearAdministrador @Login = N'jefe', @Nombre = N'Jefa', @Hash = 0x01, @Sal = 0x01, @Iteraciones = 600000, @Longitud = 12;
INSERT @t EXEC api.Usuario_Guardar @Login = N'analista', @Nombre = N'Analista', @Roles = N'Consulta', @UsuarioActual = N'jefe';
INSERT @r EXEC api.Rol_Guardar @Nombre = N'SoloSla', @Permisos = N'api.Sla_EnRiesgo', @UsuarioActual = N'jefe';
INSERT @t EXEC api.Usuario_Guardar @Login = N'externo', @Nombre = N'Externo', @Roles = N'SoloSla', @UsuarioActual = N'jefe';
INSERT @t EXEC api.Usuario_Guardar @Login = N'ajeno', @Nombre = N'Ajeno', @Roles = N'Consulta', @UsuarioActual = N'jefe';
GO

/* ===== Filtros ===== */
DECLARE @ok bit;
DECLARE @id TABLE (Id int);
INSERT @id EXEC api.Filtro_Guardar @Nombre = N'Tickets en curso', @Procedimiento = N'Issues_Buscar',
     @Parametros = N'{"TipoProyecto":"service_desk","Categoria":"indeterminate"}', @UsuarioActual = N'analista';
INSERT @id EXEC api.Filtro_Guardar @Nombre = N'Horas del mes', @Procedimiento = N'api.Horas_PorPersona',
     @Parametros = N'{"Desde":"{inicio_mes}","Hasta":"{hoy}"}', @Compartido = 1, @UsuarioActual = N'analista';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END FROM dash.Filtro WHERE PropietarioId = (SELECT UsuarioId FROM seg.Usuario WHERE Login = N'analista'));
EXEC prueba.Afirmar @ok, N'Filtros guardados (acepta el nombre con o sin "api.")';
EXEC prueba.AfirmarError N'EXEC api.Filtro_Guardar @Nombre = N''x'', @Procedimiento = N''Usuarios_Listar'', @UsuarioActual = N''analista'';', 50403, N'No se guarda un filtro de una consulta que no tiene permitida';
EXEC prueba.AfirmarError N'EXEC api.Filtro_Guardar @Nombre = N''x'', @Procedimiento = N''Sync_Solicitar'', @UsuarioActual = N''analista'';', 50400, N'No se guardan filtros de acciones';
EXEC prueba.AfirmarError N'EXEC api.Filtro_Guardar @Nombre = N''x'', @Procedimiento = N''Issues_Buscar'', @Parametros = N''{"NoExiste":1}'', @UsuarioActual = N''analista'';', 50400, N'Parámetro inexistente rechazado';
EXEC prueba.AfirmarError N'EXEC api.Filtro_Guardar @Nombre = N''x'', @Procedimiento = N''Sync_Estado'', @Parametros = N''{"UsuarioActual":"jefe"}'', @UsuarioActual = N''analista'';', 50400, N'No se pueden fijar los parámetros que pone el servidor';
EXEC prueba.AfirmarError N'EXEC api.Filtro_Guardar @Nombre = N''Tickets en curso'', @Procedimiento = N''Issues_Buscar'', @UsuarioActual = N''analista'';', 50409, N'Nombre de filtro repetido';
DECLARE @fCurso int = (SELECT FiltroId FROM dash.Filtro WHERE Nombre = N'Tickets en curso');
DECLARE @sql nvarchar(400) = CONCAT(N'EXEC api.Filtro_Guardar @FiltroId = ', @fCurso, N', @Nombre = N''robado'', @Procedimiento = N''Issues_Buscar'', @UsuarioActual = N''ajeno'';');
EXEC prueba.AfirmarError @sql, 50403, N'Solo el propietario modifica un filtro';

DECLARE @lista TABLE (FiltroId int, Nombre nvarchar(150), Procedimiento sysname, Consulta nvarchar(200), Parametros nvarchar(max), Resueltos nvarchar(max), Compartido bit,
                      Propietario nvarchar(200), EsMio bit, PuedoUsar bit, Widgets int, FechaCambio datetimeoffset);
INSERT @lista EXEC api.Filtros_Listar @UsuarioActual = N'ajeno';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 AND MAX(Nombre) = N'Horas del mes' AND MAX(Consulta) = N'Horas por persona (tabla)' AND MAX(Resueltos) NOT LIKE N'%"{%' THEN 1 ELSE 0 END FROM @lista);
EXEC prueba.Afirmar @ok, N'Otro usuario ve solo el filtro compartido (con el título de la consulta)';
DELETE @lista; INSERT @lista EXEC api.Filtros_Listar @UsuarioActual = N'externo';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM @lista);
EXEC prueba.Afirmar @ok, N'Un compartido de una consulta que el usuario no tiene permitida no se ve';
GO

/* ===== Tableros y widgets ===== */
DECLARE @ok bit;
DECLARE @id TABLE (Id int);
DECLARE @fCurso int = (SELECT FiltroId FROM dash.Filtro WHERE Nombre = N'Tickets en curso');
DECLARE @fHoras int = (SELECT FiltroId FROM dash.Filtro WHERE Nombre = N'Horas del mes');
EXEC prueba.AfirmarError N'EXEC api.Tablero_Guardar @Nombre = N''x'', @CompartirCon = N''nadie, rol:NoExiste'', @UsuarioActual = N''analista'';', 50400, N'Compartir con usuarios o roles inexistentes rechazado';
INSERT @id EXEC api.Tablero_Guardar @Nombre = N'Mesa de ayuda', @Descripcion = N'Lo del día', @CompartirCon = N'externo, analista', @UsuarioActual = N'analista';
DECLARE @tab int = (SELECT TOP (1) Id FROM @id);
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END FROM dash.TableroCompartido WHERE TableroId = @tab);
EXEC prueba.Afirmar @ok, N'Tablero compartido (el propietario no se comparte consigo mismo)';

DECLARE @sql nvarchar(max);
SET @sql = CONCAT(N'EXEC api.Widget_Guardar @TableroId = ', @tab, N', @Titulo = N''x'', @FiltroId = ', @fHoras, N', @Tipo = ''barras'', @Configuracion = N''{"valor":"HorasTotales"}'', @UsuarioActual = N''analista'';');
EXEC prueba.AfirmarError @sql, 50400, N'Barras sin columna de etiqueta rechazado';
SET @sql = CONCAT(N'EXEC api.Widget_Guardar @TableroId = ', @tab, N', @Titulo = N''x'', @FiltroId = ', @fCurso, N', @Tipo = ''indicador'', @UsuarioActual = N''jefe'';');
EXEC prueba.AfirmarError @sql, 50403, N'Solo el propietario del tablero agrega widgets (ni un administrador)';

DELETE @id;
INSERT @id EXEC api.Widget_Guardar @TableroId = @tab, @Titulo = N'Tickets en curso', @FiltroId = @fCurso, @Tipo = 'indicador',
     @Configuracion = N'{"agregacion":"conteo"}', @Ancho = 1, @UsuarioActual = N'analista';
INSERT @id EXEC api.Widget_Guardar @TableroId = @tab, @Titulo = N'Horas por persona', @FiltroId = @fHoras, @Tipo = 'barras',
     @Configuracion = N'{"etiqueta":"Persona","valor":"HorasTotales","limite":10}', @Ancho = 3, @UsuarioActual = N'analista';
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 AND MIN(Orden) = 1 AND MAX(Orden) = 2 THEN 1 ELSE 0 END FROM dash.Widget WHERE TableroId = @tab);
EXEC prueba.Afirmar @ok, N'Widgets agregados en orden';

-- El administrador tiene un filtro privado; el analista no puede usarlo.
DELETE @id; INSERT @id EXEC api.Filtro_Guardar @Nombre = N'Privado de jefa', @Procedimiento = N'Issues_Buscar', @UsuarioActual = N'jefe';
SET @sql = CONCAT(N'EXEC api.Widget_Guardar @TableroId = ', @tab, N', @Titulo = N''x'', @FiltroId = ', (SELECT TOP (1) Id FROM @id), N', @Tipo = ''tabla'', @UsuarioActual = N''analista'';');
EXEC prueba.AfirmarError @sql, 50403, N'No se usa el filtro privado de otra persona';

-- Mover: el segundo pasa a primero.
DECLARE @wBarras int = (SELECT WidgetId FROM dash.Widget WHERE TableroId = @tab AND Tipo = 'barras');
DECLARE @x TABLE (n int);
INSERT @x EXEC api.Widget_Mover @WidgetId = @wBarras, @Direccion = -1, @UsuarioActual = N'analista';
SET @ok = (SELECT CASE WHEN Orden = 1 THEN 1 ELSE 0 END FROM dash.Widget WHERE WidgetId = @wBarras);
EXEC prueba.Afirmar @ok, N'Widget movido al primer lugar';
GO

/* ===== Ver el tablero según quién lo ve ===== */
DECLARE @ok bit;
DECLARE @tab int = (SELECT TableroId FROM dash.Tablero WHERE Nombre = N'Mesa de ayuda');
DECLARE @w TABLE (WidgetId int, Titulo nvarchar(150), Tipo varchar(12), Configuracion nvarchar(max), Ancho tinyint, Orden int,
                  FiltroId int, Filtro nvarchar(150), Procedimiento sysname, Parametros nvarchar(max), ParametrosResueltos nvarchar(max), PuedoEjecutar bit);
EXEC prueba.AfirmarError N'EXEC api.Tablero_Obtener @TableroId = -1, @UsuarioActual = N''analista'';', 50404, N'Tablero inexistente';
DECLARE @s2 nvarchar(200) = CONCAT(N'EXEC api.Tablero_Obtener @TableroId = ', @tab, N', @UsuarioActual = N''ajeno'';');
EXEC prueba.AfirmarError @s2, 50403, N'Quien no tiene el tablero compartido no lo ve';

-- Los widgets (segundo resultado) se leen con una copia del procedimiento sin el primer resultado.
SELECT @ok = CASE WHEN dash.fn_PuedeVerTablero(@tab, (SELECT UsuarioId FROM seg.Usuario WHERE Login = N'externo')) = 1
                   AND dash.fn_PuedeVerTablero(@tab, (SELECT UsuarioId FROM seg.Usuario WHERE Login = N'jefe')) = 1 THEN 1 ELSE 0 END;
EXEC prueba.Afirmar @ok, N'Lo ve el usuario con quien se compartió y el administrador';

DECLARE @externo int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = N'externo');
INSERT @w
SELECT w.WidgetId, w.Titulo, w.Tipo, w.Configuracion, w.Ancho, w.Orden, f.FiltroId, f.Nombre, f.Procedimiento, f.Parametros,
       dash.fn_ResolverParametros(f.Parametros, CAST(SYSDATETIMEOFFSET() AS date)),
       CAST(CASE WHEN pp.Procedimiento IS NOT NULL THEN 1 ELSE 0 END AS bit)
FROM dash.Widget w JOIN dash.Filtro f ON f.FiltroId = w.FiltroId
LEFT JOIN seg.fn_ProcedimientosPermitidos(@externo) pp ON pp.Procedimiento = f.Procedimiento
WHERE w.TableroId = @tab;
SET @ok = (SELECT CASE WHEN COUNT(*) = 2 AND SUM(CAST(PuedoEjecutar AS int)) = 0 THEN 1 ELSE 0 END FROM @w);
EXEC prueba.Afirmar @ok, N'El externo ve el tablero pero sus widgets dicen "sin permiso" (sus roles no incluyen esas consultas)';
SET @ok = (SELECT CASE WHEN ParametrosResueltos LIKE N'{"Desde":"20__-__-01","Hasta":"20__-__-__"}' THEN 1 ELSE 0 END FROM @w WHERE Tipo = 'barras');
EXEC prueba.Afirmar @ok, N'Las fechas relativas llegan resueltas';
GO

/* ===== Inicio, eliminar y reglas finales ===== */
DECLARE @ok bit;
DECLARE @x TABLE (n int);
DECLARE @tab int = (SELECT TableroId FROM dash.Tablero WHERE Nombre = N'Mesa de ayuda');
DECLARE @fHoras int = (SELECT FiltroId FROM dash.Filtro WHERE Nombre = N'Horas del mes');
INSERT @x EXEC api.Tablero_Inicio @TableroId = @tab, @UsuarioActual = N'externo';
DECLARE @l TABLE (TableroId int, Nombre nvarchar(150), Descripcion nvarchar(400), Propietario nvarchar(200), EsMio bit, CompartidoCon nvarchar(1000), Widgets int, EsInicio bit);
INSERT @l EXEC api.Tableros_Listar @UsuarioActual = N'externo';
SET @ok = (SELECT CASE WHEN COUNT(*) = 1 AND MAX(CAST(EsInicio AS int)) = 1 AND MAX(CAST(EsMio AS int)) = 0 AND MAX(Widgets) = 2 THEN 1 ELSE 0 END FROM @l);
EXEC prueba.Afirmar @ok, N'El externo tiene el tablero compartido como pantalla de inicio';
DECLARE @sql nvarchar(400) = CONCAT(N'EXEC api.Tablero_Inicio @TableroId = ', @tab, N', @UsuarioActual = N''ajeno'';');
EXEC prueba.AfirmarError @sql, 50403, N'No se elige de inicio un tablero sin acceso';

SET @sql = CONCAT(N'EXEC api.Filtro_Eliminar @FiltroId = ', @fHoras, N', @UsuarioActual = N''analista'';');
EXEC prueba.AfirmarError @sql, 50409, N'No se elimina un filtro que usa un widget';
SET @sql = CONCAT(N'EXEC api.Tablero_Eliminar @TableroId = ', @tab, N', @UsuarioActual = N''externo'';');
EXEC prueba.AfirmarError @sql, 50403, N'Solo el propietario (o un administrador) elimina el tablero';
INSERT @x EXEC api.Tablero_Eliminar @TableroId = @tab, @UsuarioActual = N'analista';
SET @ok = (SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM dash.Widget WHERE TableroId = @tab)
                        AND (SELECT TableroInicioId FROM dash.Preferencia WHERE UsuarioId = (SELECT UsuarioId FROM seg.Usuario WHERE Login = N'externo')) IS NULL
                   THEN 1 ELSE 0 END);
EXEC prueba.Afirmar @ok, N'Al eliminar el tablero se van sus widgets y deja de ser inicio de quien lo tenía';
INSERT @x EXEC api.Filtro_Eliminar @FiltroId = @fHoras, @UsuarioActual = N'analista';
SET @ok = (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM dash.Filtro WHERE FiltroId = @fHoras);
EXEC prueba.Afirmar @ok, N'Sin widgets que lo usen, el filtro se elimina';
GO

DROP PROCEDURE prueba.AfirmarError; DROP PROCEDURE prueba.Afirmar; DROP SCHEMA prueba;
PRINT N'TODAS LAS PRUEBAS DE TABLEROS PASARON';
GO
