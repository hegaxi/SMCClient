using System.Net;
using System.Text;
using System.Text.Json;
using SMCClient.Pruebas;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>Consultas personalizadas y clientes externos a través del controlador único.</summary>
public class ClientesTests(ApiFixture bd) : IClassFixture<ApiFixture>
{
    private static async Task<(HttpStatusCode Estado, JsonElement Json)> Post(HttpClient c, string proc, object cuerpo)
    {
        var r = await c.PostAsync($"/api/procedimientos/{proc}", new StringContent(JsonSerializer.Serialize(cuerpo), Encoding.UTF8, "application/json"));
        return (r.StatusCode, JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement);
    }

    [FactSiSql]
    public async Task Un_cliente_solo_ve_las_consultas_compartidas_y_nada_interno()
    {
        await bd.CrearUsuarioAsync("cliente1", "Cliente");
        var admin = bd.ClienteAdmin();
        var cliente = bd.Cliente("cliente1");

        // El administrador publica una búsqueda como consulta personalizada para el rol Cliente.
        var (estado, pub) = await Post(admin, "ConsultaPersonalizada_Guardar", new
        {
            Nombre = "Tickets de mesa", Criterios = """[{"campo":"tipo_proyecto","operador":"en","valores":["Mesa de ayuda"]}]""",
            Columnas = "resumen,estado", CompartirCon = "rol:Cliente",
        });
        Assert.Equal(HttpStatusCode.OK, estado);
        var id = pub.GetProperty("resultados")[0].GetProperty("filas")[0].GetProperty("ConsultaId").GetInt32();

        // El menú del cliente: solo las opciones concedidas a su rol (el rol Cliente nace con "Consultas personalizadas").
        var procs = JsonDocument.Parse(await (await cliente.GetAsync("/api/procedimientos")).Content.ReadAsStringAsync()).RootElement
            .EnumerateArray().Select(p => p.GetProperty("nombre").GetString()).ToList();
        Assert.Contains("ConsultaPersonalizada_Ejecutar", procs);
        Assert.DoesNotContain("Issues_Buscar", procs);
        Assert.DoesNotContain("Issue_Detalle", procs);
        Assert.DoesNotContain("Tableros_Listar", procs);
        Assert.DoesNotContain("Sync_Estado", procs);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(cliente, "Issues_Buscar", new { })).Estado);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(cliente, "Tableros_Listar", new { })).Estado);

        // El resumen de la sincronización responde (la interfaz lo necesita); el detalle por entidad es una opción aparte.
        var (estadoSync, sync) = await Post(cliente, "Sync_Resumen", new { });
        Assert.Equal(HttpStatusCode.OK, estadoSync);
        Assert.Equal(1, sync.GetProperty("resultados").GetArrayLength());
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(cliente, "Sync_Estado", new { })).Estado);

        // Ve la consulta en su lista; sin organización asignada no ve tickets. El administrador sí.
        var lista = (await Post(cliente, "ConsultasPersonalizadas_Listar", new { })).Json.GetProperty("resultados")[0].GetProperty("filas");
        Assert.Contains(lista.EnumerateArray(), f => f.GetProperty("ConsultaId").GetInt32() == id);
        var suyos = (await Post(cliente, "ConsultaPersonalizada_Ejecutar", new { ConsultaId = id })).Json.GetProperty("resultados")[0].GetProperty("filas");
        Assert.Equal(0, suyos.GetArrayLength());
        var todos = (await Post(admin, "ConsultaPersonalizada_Ejecutar", new { ConsultaId = id })).Json.GetProperty("resultados")[0].GetProperty("filas");
        Assert.Equal("MDA-1", Assert.Single(todos.EnumerateArray()).GetProperty("Clave").GetString());

        // No puede publicar ni ver consultas que no le compartieron.
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(cliente, "ConsultaPersonalizada_Guardar", new { Nombre = "x" })).Estado);
        var (_, otra) = await Post(admin, "ConsultaPersonalizada_Guardar", new { Nombre = "Solo interna" });
        var otraId = otra.GetProperty("resultados")[0].GetProperty("filas")[0].GetProperty("ConsultaId").GetInt32();
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(cliente, "ConsultaPersonalizada_Ejecutar", new { ConsultaId = otraId })).Estado);
    }

    [FactSiSql]
    public async Task El_administrador_configura_la_frecuencia_de_sincronizacion()
    {
        var admin = bd.ClienteAdmin();
        var (estado, r) = await Post(admin, "Sync_Frecuencia_Guardar", new { Fuente = "prueba", Entidad = "comentario", FrecuenciaMin = 30 });
        Assert.Equal(HttpStatusCode.OK, estado);
        Assert.Contains(r.GetProperty("resultados")[0].GetProperty("filas").EnumerateArray(),
            f => f.GetProperty("Entidad").GetString() == "comentario" && f.GetProperty("FrecuenciaMin").GetInt32() == 30);
        Assert.Equal(HttpStatusCode.Forbidden, (await Post(bd.Cliente(), "Sync_Frecuencia_Guardar", new { Fuente = "prueba", Entidad = "issue", FrecuenciaMin = 5 })).Estado);
        Assert.Equal(HttpStatusCode.BadRequest, (await Post(admin, "Sync_Frecuencia_Guardar", new { Fuente = "prueba", Entidad = "issue", FrecuenciaMin = 0 })).Estado);
    }
}
