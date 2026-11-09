using System.Net;
using System.Text;
using System.Text.Json;
using SMCClient.Pruebas;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>Filtros y tableros a través del controlador único (las reglas están en SQL Server).</summary>
public class TablerosTests(ApiFixture bd) : IClassFixture<ApiFixture>
{
    private static async Task<JsonElement> Json(HttpResponseMessage r) => JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;

    private static async Task<JsonElement> Ejecutar(HttpClient c, string proc, object cuerpo, HttpStatusCode esperado = HttpStatusCode.OK)
    {
        var r = await c.PostAsync($"/api/procedimientos/{proc}", new StringContent(JsonSerializer.Serialize(cuerpo), Encoding.UTF8, "application/json"));
        var json = await Json(r);
        Assert.True(r.StatusCode == esperado, $"{proc}: {(int)r.StatusCode} {json}");
        return json;
    }

    private static JsonElement Filas(JsonElement r, int i = 0) => r.GetProperty("resultados")[i].GetProperty("filas");

    [FactSiSql]
    public async Task Un_usuario_arma_un_tablero_con_un_filtro_y_lo_comparte()
    {
        var lector = bd.Cliente();
        var ana = bd.Cliente("ana");

        // 1. Guarda un filtro con fecha relativa.
        var f = await Ejecutar(lector, "Filtro_Guardar", new { Nombre = "Horas desde octubre", Procedimiento = "Horas_PorPersona",
            Parametros = """{"Desde":"2026-10-01","Hasta":"{hoy}"}""", Compartido = true });
        var filtroId = Filas(f)[0].GetProperty("FiltroId").GetInt32();

        // 2. Crea un tablero compartido con ana y le agrega un widget de barras.
        var t = await Ejecutar(lector, "Tablero_Guardar", new { Nombre = "Equipo", Descripcion = "Horas del equipo", CompartirCon = "ana" });
        var tableroId = Filas(t)[0].GetProperty("TableroId").GetInt32();
        await Ejecutar(lector, "Widget_Guardar", new { TableroId = tableroId, Titulo = "Horas por persona", FiltroId = filtroId, Tipo = "barras",
            Configuracion = """{"etiqueta":"Persona","valor":"HorasTotales"}""", Ancho = 3 });

        // 3. Ana lo ve; el widget trae la consulta y los parámetros resueltos.
        var tablero = await Ejecutar(ana, "Tablero_Obtener", new { TableroId = tableroId });
        Assert.False(Filas(tablero, 0)[0].GetProperty("EsMio").GetBoolean());
        var widget = Filas(tablero, 1)[0];
        Assert.True(widget.GetProperty("PuedoEjecutar").GetBoolean());
        var parametros = JsonDocument.Parse(widget.GetProperty("ParametrosResueltos").GetString()!).RootElement;
        Assert.Equal(DateTime.Today.ToString("yyyy-MM-dd"), parametros.GetProperty("Hasta").GetString());

        // 4. Ejecutar la consulta del widget con esos parámetros devuelve los datos (con los permisos de ana).
        var datos = await Ejecutar(ana, widget.GetProperty("Procedimiento").GetString()!, parametros);
        Assert.True(Filas(datos).GetArrayLength() > 0);

        // 5. Ana no puede modificarlo; un tercero no lo ve.
        await Ejecutar(ana, "Widget_Guardar", new { TableroId = tableroId, Titulo = "x", FiltroId = filtroId, Tipo = "tabla" }, HttpStatusCode.Forbidden);
        await bd.CrearUsuarioAsync("tercero", "Consulta");
        await Ejecutar(bd.Cliente("tercero"), "Tablero_Obtener", new { TableroId = tableroId }, HttpStatusCode.Forbidden);

        // 6. Ana lo elige como su tablero de inicio.
        await Ejecutar(ana, "Tablero_Inicio", new { TableroId = tableroId });
        var lista = await Ejecutar(ana, "Tableros_Listar", new { });
        Assert.Contains(Filas(lista).EnumerateArray(), x => x.GetProperty("TableroId").GetInt32() == tableroId && x.GetProperty("EsInicio").GetBoolean());
    }

    [FactSiSql]
    public async Task El_propietario_lo_pone_el_servidor_y_las_reglas_de_SQL_llegan_al_usuario()
    {
        var lector = bd.Cliente();
        // No se puede guardar un filtro "a nombre de otro": UsuarioActual lo pone el servidor.
        await Ejecutar(lector, "Filtro_Guardar", new { Nombre = "x", Procedimiento = "Issues_Buscar", UsuarioActual = "admin" }, HttpStatusCode.BadRequest);
        // Consultas de administración: sin permiso (regla de SQL, 403).
        var r = await Ejecutar(lector, "Filtro_Guardar", new { Nombre = "Usuarios", Procedimiento = "Usuarios_Listar" }, HttpStatusCode.Forbidden);
        Assert.Equal("No tiene permiso para esa consulta.", r.GetProperty("title").GetString());
    }
}
