using System.Net;
using System.Text;
using System.Text.Json;
using SMCClient.Pruebas;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>Tiempo reportado en Scrum a través del controlador único (los cálculos están en SQL Server).</summary>
public class TiemposScrumTests(ApiFixture bd) : IClassFixture<ApiFixture>
{
    private static async Task<JsonElement> Filas(HttpClient c, string proc, object cuerpo)
    {
        var r = await c.PostAsync($"/api/procedimientos/{proc}", new StringContent(JsonSerializer.Serialize(cuerpo), Encoding.UTF8, "application/json"));
        var json = JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;
        Assert.True(r.StatusCode == HttpStatusCode.OK, $"{proc}: {(int)r.StatusCode} {json}");
        return json.GetProperty("resultados")[0].GetProperty("filas");
    }

    [FactSiSql]
    public async Task Horas_por_sprint_y_persona_y_avance_con_horas_dentro_del_sprint()
    {
        var lector = bd.Cliente();
        var porSprint = await Filas(lector, "Horas_PorSprint", new { Proyecto = "SCR" });
        var fila = Assert.Single(porSprint.EnumerateArray());   // el worklog del 20 de octubre cae en el Sprint 4
        Assert.Equal("Sprint 4", fila.GetProperty("Sprint").GetString());
        Assert.Equal("Dev Uno", fila.GetProperty("Persona").GetString());
        Assert.Equal(8m, fila.GetProperty("HorasRegistradas").GetDecimal());

        var avance = await Filas(lector, "Sprint_Avance", new { Proyecto = "SCR" });
        Assert.Equal(8m, avance.EnumerateArray().Single(f => f.GetProperty("Sprint").GetString() == "Sprint 4").GetProperty("HorasRegistradas").GetDecimal());
        Assert.Equal(JsonValueKind.Null, avance.EnumerateArray().Single(f => f.GetProperty("Sprint").GetString() == "Sprint 3").GetProperty("HorasRegistradas").ValueKind);

        var campos = await Filas(lector, "Issues_Campos", new { });
        Assert.Contains(campos.EnumerateArray(), c => c.GetProperty("Clave").GetString() == "horas_registradas");
        Assert.Contains(campos.EnumerateArray(), c => c.GetProperty("Clave").GetString() == "registro_persona");
        Assert.Contains(campos.EnumerateArray(), c => c.GetProperty("Clave").GetString() == "epica");
        Assert.Contains(campos.EnumerateArray(), c => c.GetProperty("Clave").GetString() == "jerarquia");

        // Los datos de prueba de la API no tienen épicas: el reporte responde vacío, no con error.
        Assert.Equal(0, (await Filas(lector, "Epicas_Avance", new { Proyecto = "SCR" })).GetArrayLength());
        var conEpica = await Filas(lector, "Horas_PorPersona", new { Desde = "2026-10-01", Hasta = "2026-11-30", Epica = "SCR-1" });
        Assert.Equal(0, conEpica.GetArrayLength());

        // Estimado vs. real: SCR-7 es una historia sin estimación (la captura se mide).
        var resumen = (await Filas(lector, "Estimacion_VsReal", new { Proyecto = "SCR" }))[0];
        Assert.Equal(1, resumen.GetProperty("Issues").GetInt32());
        Assert.Equal(1, resumen.GetProperty("SinEstimacion").GetInt32());
    }
}
