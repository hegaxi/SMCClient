using System.Net;
using System.Text;
using System.Text.Json;
using SMCClient.Pruebas;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>Búsqueda avanzada a través del controlador único, con el login de SQL que solo tiene el rol smc_api.</summary>
public class BuscadorTests(ApiFixture bd) : IClassFixture<ApiFixture>
{
    private static async Task<JsonElement> Ejecutar(HttpClient c, string proc, object cuerpo, HttpStatusCode esperado = HttpStatusCode.OK)
    {
        var r = await c.PostAsync($"/api/procedimientos/{proc}", new StringContent(JsonSerializer.Serialize(cuerpo), Encoding.UTF8, "application/json"));
        var json = JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;
        Assert.True(r.StatusCode == esperado, $"{proc}: {(int)r.StatusCode} {json}");
        return json;
    }

    private static JsonElement Filas(JsonElement r) => r.GetProperty("resultados")[0].GetProperty("filas");

    [FactSiSql]
    public async Task El_menu_muestra_la_busqueda_y_oculta_sus_procedimientos_auxiliares()
    {
        var r = await bd.Cliente().GetAsync("/api/procedimientos");
        var procs = JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement.EnumerateArray().ToList();
        var consultar = procs.Single(p => p.GetProperty("nombre").GetString() == "Issues_Consultar");
        Assert.Equal("Búsqueda avanzada", consultar.GetProperty("titulo").GetString());
        Assert.False(consultar.GetProperty("oculto").GetBoolean());
        Assert.True(procs.Single(p => p.GetProperty("nombre").GetString() == "Issues_Campos").GetProperty("oculto").GetBoolean());
        Assert.True(procs.Single(p => p.GetProperty("nombre").GetString() == "Issues_Valores").GetProperty("oculto").GetBoolean());
        Assert.True(procs.Single(p => p.GetProperty("nombre").GetString() == "Issues_Resumir").GetProperty("oculto").GetBoolean());
    }

    [FactSiSql]
    public async Task Busca_con_criterios_columnas_y_orden_con_permisos_minimos()
    {
        var lector = bd.Cliente();
        var campos = Filas(await Ejecutar(lector, "Issues_Campos", new { }));
        Assert.Contains(campos.EnumerateArray(), c => c.GetProperty("Clave").GetString() == "cf:customfield_10468");

        var valores = Filas(await Ejecutar(lector, "Issues_Valores", new { Campo = "estado" }));
        Assert.Equal(2, valores.GetArrayLength());

        var criterios = """[{"campo":"estado","operador":"no_en","valores":["Done"]},{"campo":"creado","operador":"desde","valor":"{inicio_anio}"}]""";
        var res = Filas(await Ejecutar(lector, "Issues_Consultar", new { Criterios = criterios, Columnas = "resumen,etiquetas,cf:customfield_10468", OrdenarPor = "clave", Descendente = false }));
        var fila = Assert.Single(res.EnumerateArray());
        Assert.Equal("MDA-1", fila.GetProperty("Clave").GetString());
        Assert.Contains("urgente", fila.GetProperty("Etiquetas").GetString());
        Assert.Equal(1, fila.GetProperty("TotalFilas").GetInt32());
        Assert.Equal(["Clave", "Resumen", "Etiquetas", "Estación", "TotalFilas"], fila.EnumerateObject().Select(p => p.Name));
    }

    [FactSiSql]
    public async Task Resume_en_SQL_sobre_todos_los_issues_del_filtro()
    {
        var lector = bd.Cliente();
        var porProyecto = Filas(await Ejecutar(lector, "Issues_Resumir", new { AgruparPor = "proyecto", Agregacion = "suma", Valor = "horas" }));
        Assert.Equal(["SCR", "MDA"], porProyecto.EnumerateArray().Select(f => f.GetProperty("Grupo").GetString()));
        Assert.Equal(8m, porProyecto[0].GetProperty("Valor").GetDecimal());
        Assert.Equal("Horas invertidas", porProyecto[0].GetProperty("EtiquetaValor").GetString());

        var abiertos = Filas(await Ejecutar(lector, "Issues_Resumir", new { Criterios = """[{"campo":"abierto","operador":"es","valor":"1"}]""" }));
        Assert.Equal(1m, Assert.Single(abiertos.EnumerateArray()).GetProperty("Valor").GetDecimal());

        await Ejecutar(lector, "Issues_Resumir", new { Agregacion = "suma", Valor = "estado" }, HttpStatusCode.BadRequest);
    }

    [FactSiSql]
    public async Task Rechaza_campos_y_columnas_fuera_de_la_lista_blanca()
    {
        var lector = bd.Cliente();
        var e = await Ejecutar(lector, "Issues_Consultar", new { Criterios = """[{"campo":"1=1; DROP TABLE ops.Issue --","operador":"igual","valor":"1"}]""" }, HttpStatusCode.BadRequest);
        Assert.Contains("Campos desconocidos", e.GetProperty("title").GetString());
        await Ejecutar(lector, "Issues_Consultar", new { Columnas = "resumen,(SELECT name FROM sys.sql_logins)" }, HttpStatusCode.BadRequest);
        await Ejecutar(lector, "Issues_Consultar", new { OrdenarPor = "clave desc; --" }, HttpStatusCode.BadRequest);
    }
}
