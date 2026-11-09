using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using SMCClient.Pruebas;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>Controlador único contra una base real desplegada con los scripts del repositorio.</summary>
public class ProcedimientosControllerTests(ApiFixture bd) : IClassFixture<ApiFixture>
{
    private static async Task<JsonElement> Json(HttpResponseMessage r) => JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;

    private static Task<HttpResponseMessage> Post(HttpClient c, string proc, string? json) =>
        c.PostAsync($"/api/procedimientos/{proc}", json is null ? null : new StringContent(json, Encoding.UTF8, "application/json"));

    private static JsonElement Proc(JsonElement lista, string nombre) => lista.EnumerateArray().Single(p => p.GetProperty("nombre").GetString() == nombre);

    [FactSiSql]
    public async Task Sin_sesion_responde_401_y_salud_es_anonima()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await bd.Anonimo().GetAsync("/api/procedimientos")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Post(bd.Anonimo(), "Issues_Buscar", null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await bd.Anonimo().GetAsync("/salud")).StatusCode);
    }

    [FactSiSql]
    public async Task Las_peticiones_que_modifican_requieren_el_encabezado_anti_CSRF()
    {
        var sinEncabezado = bd.Cliente();
        sinEncabezado.DefaultRequestHeaders.Remove(SMCClient.Api.Seguridad.Politicas.EncabezadoSolicitud);
        var r = await Post(sinEncabezado, "Issues_Buscar", null);
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
        Assert.Equal("solicitud.invalida", (await Json(r)).GetProperty("codigo").GetString());
    }

    [FactSiSql]
    public async Task Los_permisos_los_decide_SQL_Server_y_se_aplican_de_inmediato()
    {
        var admin = bd.ClienteAdmin();
        var lector = bd.Cliente();
        Assert.DoesNotContain("Auditoria_Listar", await Nombres(lector));

        Assert.Equal(HttpStatusCode.OK, (await Post(admin, "Rol_Guardar", """{"Nombre":"Auditor","Permisos":"api.Auditoria_Listar"}""")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Post(admin, "Usuario_Guardar", """{"Login":"lector","Roles":"Consulta, Auditor"}""")).StatusCode);
        Assert.Contains("Auditoria_Listar", await Nombres(lector));                 // sin esperar al caché
        Assert.Equal(HttpStatusCode.OK, (await Post(lector, "Auditoria_Listar", null)).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await Post(admin, "Usuario_Guardar", """{"Login":"lector","Roles":"Consulta"}""")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(lector, "Auditoria_Listar", null)).StatusCode);

        // Las reglas de negocio de SQL llegan al usuario: un administrador no puede quitarse la administración.
        var r = await Post(admin, "Usuario_Guardar", """{"Login":"admin","Roles":"Consulta"}""");
        Assert.Equal(HttpStatusCode.Conflict, r.StatusCode);
        Assert.Contains("a sí mismo", (await Json(r)).GetProperty("title").GetString());
        // Y la auditoría registra quién hizo el cambio (el servidor pone @UsuarioActual).
        Assert.Equal("admin", await bd.EscalarAsync<string>("SELECT TOP (1) Usuario FROM seg.Auditoria WHERE Accion = 'usuario.guardar' AND Objeto = 'lector' ORDER BY AuditoriaId DESC"));
    }

    private static async Task<List<string?>> Nombres(HttpClient c) =>
        (await Json(await c.GetAsync("/api/procedimientos"))).EnumerateArray().Select(p => p.GetProperty("nombre").GetString()).ToList();

    [FactSiSql]
    public async Task Lista_los_procedimientos_con_sus_metadatos_segun_el_permiso_del_usuario()
    {
        var lector = await Json(await bd.Cliente().GetAsync("/api/procedimientos"));
        var admin = await Json(await bd.ClienteAdmin().GetAsync("/api/procedimientos"));

        var nombresLector = lector.EnumerateArray().Select(p => p.GetProperty("nombre").GetString()).ToList();
        Assert.Contains("Issues_Buscar", nombresLector);
        Assert.DoesNotContain("Mapeo_Establecer", nombresLector);            // smc:permiso = admin
        Assert.Contains("Mapeo_Establecer", admin.EnumerateArray().Select(p => p.GetProperty("nombre").GetString()));

        var buscar = Proc(lector, "Issues_Buscar");
        Assert.Equal("Búsqueda rápida", buscar.GetProperty("titulo").GetString());
        Assert.StartsWith("Historias Scrum y tickets", buscar.GetProperty("descripcion").GetString());
        Assert.False(buscar.GetProperty("exentoSync").GetBoolean());
        var proyecto = buscar.GetProperty("parametros").EnumerateArray().Single(p => p.GetProperty("nombre").GetString() == "Proyecto");
        Assert.Equal("varchar", proyecto.GetProperty("tipo").GetString());
        Assert.Equal(50, proyecto.GetProperty("longitud").GetInt32());
        Assert.True(proyecto.GetProperty("opcional").GetBoolean());
        Assert.Equal("Vacío = todos los proyectos", proyecto.GetProperty("descripcion").GetString());
        // smc:origen: el proyecto se elige de la lista de Proyectos_Listar (Clave, con el nombre como descripción).
        var origen = proyecto.GetProperty("origen");
        Assert.Equal("Proyectos_Listar", origen.GetProperty("procedimiento").GetString());
        Assert.Equal("Clave", origen.GetProperty("valor").GetString());
        Assert.Equal("Nombre", origen.GetProperty("descripcion").GetString());
        Assert.False(origen.GetProperty("libre").GetBoolean());
        Assert.Equal(JsonValueKind.Null, proyecto.GetProperty("multiple").ValueKind);
        Assert.Contains(buscar.GetProperty("columnas").EnumerateArray(), c => c.GetProperty("nombre").GetString() == "Clave");

        var desde = Proc(lector, "Horas_PorPersona").GetProperty("parametros").EnumerateArray().Single(p => p.GetProperty("nombre").GetString() == "Desde");
        Assert.Equal("date", desde.GetProperty("tipo").GetString());
        Assert.False(desde.GetProperty("opcional").GetBoolean());

        Assert.True(Proc(lector, "Sync_Estado").GetProperty("exentoSync").GetBoolean());
        Assert.True(Proc(lector, "Sync_Solicitar").GetProperty("accion").GetBoolean());
        Assert.DoesNotContain(Proc(admin, "Usuario_Guardar").GetProperty("parametros").EnumerateArray(), p => p.GetProperty("nombre").GetString() == "UsuarioActual");
        Assert.False(buscar.GetProperty("accion").GetBoolean());
        Assert.Equal("Tiempo registrado", Proc(lector, "Issue_Detalle").GetProperty("titulosResultados")[2].GetString());
        var tipo = buscar.GetProperty("parametros").EnumerateArray().Single(p => p.GetProperty("nombre").GetString() == "TipoProyecto");
        Assert.Contains(tipo.GetProperty("opciones").EnumerateArray(), o => o.GetProperty("valor").GetString() == "service_desk" && o.GetProperty("etiqueta").GetString() == "Mesa de ayuda");
        // @SolicitadoPor lo llena el servidor: no se expone.
        Assert.DoesNotContain(Proc(lector, "Sync_Solicitar").GetProperty("parametros").EnumerateArray(), p => p.GetProperty("nombre").GetString() == "SolicitadoPor");
    }

    [FactSiSql]
    public async Task Ejecuta_con_parametros_tipados_y_devuelve_filas_con_los_nombres_de_columna()
    {
        var r = await Post(bd.Cliente(), "Issues_Buscar", """{"TipoProyecto":"service_desk"}""");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var fila = (await Json(r)).GetProperty("resultados")[0].GetProperty("filas")[0];
        Assert.Equal("MDA-1", fila.GetProperty("Clave").GetString());
        Assert.Equal(1, fila.GetProperty("TotalFilas").GetInt32());

        var horas = (await Json(await Post(bd.Cliente(), "api.Horas_PorPersona", """{"@Desde":"2026-10-01","Hasta":"2026-11-30"}""")))
            .GetProperty("resultados")[0].GetProperty("filas").EnumerateArray().ToList();
        Assert.Equal(10m, horas.Sum(f => f.GetProperty("HorasRegistradas").GetDecimal()));
        Assert.Equal(16m, horas.Sum(f => f.GetProperty("HorasAutomaticas").GetDecimal()));

        var origen = await Post(bd.Cliente(), "Horas_PorPersona", """{"Desde":"2026-10-01","Hasta":"2026-11-30","Origen":"otro"}""");
        Assert.Equal(HttpStatusCode.BadRequest, origen.StatusCode);

        var detalle = await Json(await Post(bd.Cliente(), "Issue_Detalle", """{"Clave":"MDA-1"}"""));
        Assert.Equal(6, detalle.GetProperty("resultados").GetArrayLength());   // issue, campos, worklogs, SLA, historial, comentarios
    }

    [TheorySiSql]
    [InlineData("Horas_PorPersona", "{}", "Desde")]                                          // obligatorio
    [InlineData("Horas_PorPersona", """{"Desde":"ayer","Hasta":"2026-11-30"}""", "Desde")]    // tipo
    [InlineData("Issues_Buscar", """{"NoExiste":1}""", "NoExiste")]                           // desconocido
    [InlineData("Issues_Buscar", """{"Pagina":"uno"}""", "Pagina")]                           // tipo
    [InlineData("Issues_Buscar", """{"Pagina":99999999999}""", "Pagina")]                     // fuera de rango
    [InlineData("Issues_Buscar", """{"Proyecto":"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"}""", "Proyecto")]  // longitud
    public async Task Valida_los_parametros_antes_de_llamar_a_SQL(string proc, string cuerpo, string parametro)
    {
        var r = await Post(bd.Cliente(), proc, cuerpo);
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
        var pd = await Json(r);
        Assert.Equal("parametro.invalido", pd.GetProperty("codigo").GetString());
        Assert.True(pd.GetProperty("errors").TryGetProperty(parametro, out _));
    }

    [FactSiSql]
    public async Task Cuerpo_invalido_responde_400()
    {
        Assert.Equal(HttpStatusCode.BadRequest, (await Post(bd.Cliente(), "Issues_Buscar", "[1,2]")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Post(bd.Cliente(), "Issues_Buscar", "{no es json")).StatusCode);
    }

    [FactSiSql]
    public async Task Los_errores_de_negocio_de_SQL_llegan_con_su_mensaje_y_estado()
    {
        var r = await Post(bd.Cliente(), "Issue_Detalle", """{"Clave":"NO-1"}""");
        Assert.Equal(HttpStatusCode.NotFound, r.StatusCode);   // THROW 50404
        var pd = await Json(r);
        Assert.Equal("No existe el issue.", pd.GetProperty("title").GetString());
        Assert.Equal("sql.50404", pd.GetProperty("codigo").GetString());
    }

    [FactSiSql]
    public async Task Solo_ejecuta_procedimientos_del_catalogo_y_con_permiso()
    {
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(bd.Cliente(), "Mapeo_Establecer", """{"Fuente":"prueba","Rol":"sprint"}""")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await Post(bd.Cliente(), "Issues_Buscar;DROP TABLE ops.Issue", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await Post(bd.ClienteAdmin(), "sync.Reprocesar", """{"Fuente":"prueba"}""")).StatusCode);   // otro esquema
        Assert.Equal(HttpStatusCode.OK, (await Post(bd.ClienteAdmin(), "Mapeos_Listar", null)).StatusCode);
    }

    [FactSiSql]
    public async Task Responde_503_mientras_una_fuente_no_esta_sincronizada()
    {
        await bd.EjecutarAsync("EXEC sync.Fuente_Registrar @Codigo = 'nueva', @UrlBase = N'https://nueva.atlassian.net';");
        try
        {
            var r = await Post(bd.Cliente(), "Issues_Buscar", null);
            Assert.Equal(HttpStatusCode.ServiceUnavailable, r.StatusCode);
            Assert.Equal("15", r.Headers.RetryAfter?.ToString());
            var pd = await Json(r);
            Assert.Equal("sync.pendiente", pd.GetProperty("codigo").GetString());
            Assert.Contains(pd.GetProperty("fuentes").EnumerateArray(), f => f.GetProperty("fuente").GetString() == "nueva");

            // Los procedimientos exentos (estado de la sincronización) sí responden.
            Assert.Equal(HttpStatusCode.OK, (await Post(bd.Cliente(), "Sync_Estado", null)).StatusCode);
        }
        finally
        {
            await bd.EjecutarAsync("UPDATE cfg.Fuente SET Activa = 0 WHERE Codigo = 'nueva';");
        }
        Assert.Equal(HttpStatusCode.OK, (await Post(bd.Cliente(), "Issues_Buscar", null)).StatusCode);
    }

    [FactSiSql]
    public async Task Despues_de_la_primera_carga_los_datos_atrasados_no_bloquean()
    {
        // Jira o el worker llevan dos días sin sincronizar: la API sigue respondiendo con lo que tiene y avisa del atraso.
        const string mover = "UPDATE e SET Inicio = DATEADD(DAY, {0}, Inicio), Fin = DATEADD(DAY, {0}, Fin) FROM sync.Ejecucion e JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId WHERE f.Codigo = 'prueba';";
        await bd.EjecutarAsync(string.Format(mover, -2));
        try
        {
            Assert.Equal(HttpStatusCode.OK, (await Post(bd.Cliente(), "Issues_Buscar", null)).StatusCode);
            var estado = await Json(await Post(bd.Cliente(), "Sync_Estado", null));
            var fila = estado.GetProperty("resultados")[0].GetProperty("filas").EnumerateArray().Single(f => f.GetProperty("Fuente").GetString() == "prueba");
            Assert.True(fila.GetProperty("DatosVigentes").GetBoolean());
            Assert.True(fila.GetProperty("DatosAtrasados").GetBoolean());
        }
        finally
        {
            await bd.EjecutarAsync(string.Format(mover, 2));
        }
    }

    [FactSiSql]
    public async Task El_usuario_de_la_solicitud_lo_pone_el_servidor()
    {
        Assert.Equal(HttpStatusCode.OK, (await Post(bd.Cliente("ana"), "Sync_Solicitar", """{"Fuente":"prueba"}""")).StatusCode);
        Assert.Equal("ana", await bd.EscalarAsync<string>("SELECT TOP (1) SolicitadoPor FROM sync.Solicitud WHERE Modo = 'incremental' ORDER BY SolicitudId DESC"));
        Assert.Equal(HttpStatusCode.BadRequest, (await Post(bd.Cliente(), "Sync_Solicitar", """{"SolicitadoPor":"otra persona"}""")).StatusCode);
    }

    [FactSiSql]
    public async Task Un_procedimiento_nuevo_en_la_base_aparece_sin_reiniciar_la_API()
    {
        await bd.EjecutarAsync("""
            CREATE OR ALTER PROCEDURE api.Prueba_Nueva @Nombre nvarchar(20) = N'mundo' AS SELECT N'hola ' + @Nombre AS Saludo;
            """);
        await bd.EjecutarAsync("EXEC adm.Descripcion_Establecer 'api.Prueba_Nueva', NULL, N'smc:permiso', N'lectura';");
        try
        {
            var lista = await Json(await bd.Cliente().GetAsync("/api/procedimientos"));
            Assert.Equal("Saludo", Proc(lista, "Prueba_Nueva").GetProperty("columnas")[0].GetProperty("nombre").GetString());
            var r = await Json(await Post(bd.Cliente(), "Prueba_Nueva", """{"Nombre":"SMC"}"""));
            Assert.Equal("hola SMC", r.GetProperty("resultados")[0].GetProperty("filas")[0].GetProperty("Saludo").GetString());
        }
        finally
        {
            await bd.EjecutarAsync("DROP PROCEDURE api.Prueba_Nueva;");
        }
        Assert.Equal(HttpStatusCode.NotFound, (await Post(bd.Cliente(), "Prueba_Nueva", null)).StatusCode);
    }
}
