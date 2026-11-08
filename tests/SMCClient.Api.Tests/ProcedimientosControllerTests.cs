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
    public async Task Sin_usuario_autenticado_responde_401_y_salud_es_anonima()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await bd.Cliente(usuario: null).GetAsync("/api/procedimientos")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await bd.Cliente(usuario: null).GetAsync("/salud")).StatusCode);
    }

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
        Assert.Equal("Búsqueda de historias y tickets.", buscar.GetProperty("descripcion").GetString());
        Assert.False(buscar.GetProperty("exentoSync").GetBoolean());
        var proyecto = buscar.GetProperty("parametros").EnumerateArray().Single(p => p.GetProperty("nombre").GetString() == "Proyecto");
        Assert.Equal("varchar", proyecto.GetProperty("tipo").GetString());
        Assert.Equal(50, proyecto.GetProperty("longitud").GetInt32());
        Assert.True(proyecto.GetProperty("opcional").GetBoolean());
        Assert.Equal("Clave del proyecto (p. ej. SMC26)", proyecto.GetProperty("descripcion").GetString());
        Assert.Contains(buscar.GetProperty("columnas").EnumerateArray(), c => c.GetProperty("nombre").GetString() == "Clave");

        var desde = Proc(lector, "Horas_PorPersona").GetProperty("parametros").EnumerateArray().Single(p => p.GetProperty("nombre").GetString() == "Desde");
        Assert.Equal("date", desde.GetProperty("tipo").GetString());
        Assert.False(desde.GetProperty("opcional").GetBoolean());

        Assert.True(Proc(lector, "Sync_Estado").GetProperty("exentoSync").GetBoolean());
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

        var horas = await Json(await Post(bd.Cliente(), "api.Horas_PorPersona", """{"@Desde":"2026-10-01","Hasta":"2026-11-30"}"""));
        Assert.Equal(10m, horas.GetProperty("resultados")[0].GetProperty("filas").EnumerateArray().Sum(f => f.GetProperty("Horas").GetDecimal()));

        var detalle = await Json(await Post(bd.Cliente(), "Issue_Detalle", """{"Clave":"MDA-1"}"""));
        Assert.Equal(5, detalle.GetProperty("resultados").GetArrayLength());   // issue, campos, worklogs, SLA, historial
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
    public async Task El_usuario_de_la_solicitud_lo_pone_el_servidor()
    {
        Assert.Equal(HttpStatusCode.OK, (await Post(bd.Cliente("DOMINIO\\ana"), "Sync_Solicitar", """{"Fuente":"prueba"}""")).StatusCode);
        Assert.Equal("DOMINIO\\ana", await bd.EscalarAsync<string>("SELECT TOP (1) SolicitadoPor FROM sync.Solicitud WHERE Modo = 'incremental' ORDER BY SolicitudId DESC"));
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
