using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using SMCClient.Pruebas;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>Usuarios y contraseñas en SQL Server: inicio de sesión con cookie y reglas decididas por la base.</summary>
public class SesionTests(ApiFixture bd) : IClassFixture<ApiFixture>
{
    private static async Task<JsonElement> Json(HttpResponseMessage r) => JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement;

    private static Task<HttpResponseMessage> Procedimientos(HttpClient c) => c.GetAsync("/api/procedimientos");

    [FactSiSql]
    public async Task Inicia_sesion_y_la_cookie_es_segura()
    {
        var c = bd.Anonimo();
        var r = await bd.IniciarAsync(c, "lector");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var s = await Json(r);
        Assert.Equal("lector", s.GetProperty("usuario").GetString());
        Assert.Equal("Consulta", s.GetProperty("roles").GetString());
        Assert.False(s.GetProperty("debeCambiarContrasena").GetBoolean());

        var cookie = r.Headers.GetValues("Set-Cookie").Single(v => v.StartsWith("smc_sesion="));
        Assert.Contains("httponly", cookie, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("samesite=strict", cookie, StringComparison.OrdinalIgnoreCase);

        Assert.Equal(HttpStatusCode.OK, (await c.GetAsync("/api/sesion")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Procedimientos(c)).StatusCode);

        Assert.Equal(HttpStatusCode.NoContent, (await c.PostAsync("/api/sesion/cerrar", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Procedimientos(c)).StatusCode);
    }

    [FactSiSql]
    public async Task Contrasena_incorrecta_y_usuario_inexistente_responden_igual()
    {
        var mala = await bd.IniciarAsync(bd.Anonimo(), "lector", "otra-cosa-123");
        var nadie = await bd.IniciarAsync(bd.Anonimo(), "no-existe", "otra-cosa-123");
        Assert.Equal(HttpStatusCode.Unauthorized, mala.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, nadie.StatusCode);
        Assert.Equal((await Json(mala)).GetProperty("title").GetString(), (await Json(nadie)).GetProperty("title").GetString());
    }

    [FactSiSql]
    public async Task Bloquea_la_cuenta_tras_cinco_intentos_fallidos()
    {
        await bd.CrearUsuarioAsync("bloqueable", "Consulta");
        for (var i = 0; i < 5; i++) await bd.IniciarAsync(bd.Anonimo(), "bloqueable", "incorrecta-123");
        Assert.Equal(HttpStatusCode.Unauthorized, (await bd.IniciarAsync(bd.Anonimo(), "bloqueable")).StatusCode);   // ni con la correcta
        Assert.True(await bd.EscalarAsync<bool>("SELECT CAST(CASE WHEN BloqueadoHasta > SYSDATETIMEOFFSET() THEN 1 ELSE 0 END AS bit) FROM seg.Usuario WHERE Login = 'bloqueable'"));
        Assert.Equal(1, await bd.EscalarAsync<int>("SELECT COUNT(*) FROM seg.Auditoria WHERE Accion = 'sesion.bloqueo' AND Objeto = 'bloqueable'"));
    }

    [FactSiSql]
    public async Task El_administrador_restablece_y_el_usuario_debe_cambiarla_al_entrar()
    {
        var admin = bd.ClienteAdmin();
        Assert.Equal(HttpStatusCode.OK, (await admin.PostAsync("/api/procedimientos/Usuario_Guardar",
            new StringContent("""{"Login":"nuevo","Nombre":"Usuario Nuevo","Roles":"Consulta"}""", Encoding.UTF8, "application/json"))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await bd.IniciarAsync(bd.Anonimo(), "nuevo", "lo-que-sea-123")).StatusCode);   // aún sin contraseña

        var corta = await admin.PostAsJsonAsync("/api/sesion/restablecer-contrasena", new { usuario = "nuevo", contrasenaTemporal = "corta" });
        Assert.Equal(HttpStatusCode.BadRequest, corta.StatusCode);
        Assert.Contains("al menos 10", (await Json(corta)).GetProperty("title").GetString());   // regla de la base
        Assert.Equal(HttpStatusCode.NoContent, (await admin.PostAsJsonAsync("/api/sesion/restablecer-contrasena", new { usuario = "nuevo", contrasenaTemporal = "Temporal-2026" })).StatusCode);

        var nuevo = bd.Anonimo();
        var inicio = await Json(await bd.IniciarAsync(nuevo, "nuevo", "Temporal-2026"));
        Assert.True(inicio.GetProperty("debeCambiarContrasena").GetBoolean());
        var bloqueado = await Procedimientos(nuevo);
        Assert.Equal(HttpStatusCode.Forbidden, bloqueado.StatusCode);
        Assert.Equal("contrasena.debe_cambiar", (await Json(bloqueado)).GetProperty("codigo").GetString());

        Assert.Equal(HttpStatusCode.BadRequest, (await nuevo.PostAsJsonAsync("/api/sesion/cambiar-contrasena", new { actual = "equivocada-1", nueva = "Definitiva-2026" })).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await nuevo.PostAsJsonAsync("/api/sesion/cambiar-contrasena", new { actual = "Temporal-2026", nueva = "Definitiva-2026" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Procedimientos(nuevo)).StatusCode);                                   // la misma sesión sigue
        Assert.Equal(HttpStatusCode.OK, (await bd.IniciarAsync(bd.Anonimo(), "nuevo", "Definitiva-2026")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await bd.IniciarAsync(bd.Anonimo(), "nuevo", "Temporal-2026")).StatusCode);
    }

    [FactSiSql]
    public async Task Cambiar_la_contrasena_cierra_las_demas_sesiones()
    {
        await bd.CrearUsuarioAsync("dos_sesiones", "Consulta");
        var a = bd.Cliente("dos_sesiones");
        var b = bd.Cliente("dos_sesiones");
        Assert.Equal(HttpStatusCode.NoContent, (await a.PostAsJsonAsync("/api/sesion/cambiar-contrasena", new { actual = ApiFixture.Clave, nueva = "Otra-Clave-2026" })).StatusCode);

        var r = await Procedimientos(b);
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
        Assert.Equal("sesion.invalida", (await Json(r)).GetProperty("codigo").GetString());
        Assert.Equal(HttpStatusCode.OK, (await Procedimientos(a)).StatusCode);
    }

    [FactSiSql]
    public async Task Desactivar_a_un_usuario_cierra_su_sesion()
    {
        await bd.CrearUsuarioAsync("temporal", "Consulta");
        var t = bd.Cliente("temporal");
        Assert.Equal(HttpStatusCode.OK, (await Procedimientos(t)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await bd.ClienteAdmin().PostAsync("/api/procedimientos/Usuario_Guardar",
            new StringContent("""{"Login":"temporal","Activo":false,"Roles":""}""", Encoding.UTF8, "application/json"))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Procedimientos(t)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await bd.IniciarAsync(bd.Anonimo(), "temporal")).StatusCode);
    }

    [FactSiSql]
    public async Task Solo_un_administrador_restablece_contrasenas_de_otros()
    {
        var r = await bd.Cliente().PostAsJsonAsync("/api/sesion/restablecer-contrasena", new { usuario = "admin", contrasenaTemporal = "Intento-de-robo-1" });
        Assert.Equal(HttpStatusCode.Forbidden, r.StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await bd.IniciarAsync(bd.Anonimo(), "admin")).StatusCode);   // la del admin no cambió
    }

    [FactSiSql]
    public async Task El_comando_de_instalacion_crea_un_administrador_sin_pasar_la_contrasena_por_SQL()
    {
        var dll = Path.Combine(BaseDatosPrueba.RaizDb(), "..", "src", "SMCClient.Api", "bin", "Debug", "net8.0", "SMCClient.Api.dll");
        var psi = new ProcessStartInfo("dotnet", $"\"{dll}\" crear-administrador --usuario instalador --nombre \"Instalador\" --cadena \"{bd.Cadena}\"")
        {
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        };
        using var p = Process.Start(psi)!;
        await p.StandardInput.WriteLineAsync("Instalacion-2026");
        await p.StandardInput.WriteLineAsync("Instalacion-2026");
        p.StandardInput.Close();
        var salida = await p.StandardOutput.ReadToEndAsync() + await p.StandardError.ReadToEndAsync();
        await p.WaitForExitAsync();

        Assert.True(p.ExitCode == 0, salida);
        var s = await Json(await bd.IniciarAsync(bd.Anonimo(), "instalador", "Instalacion-2026"));
        Assert.Contains("Administrador", s.GetProperty("roles").GetString());
        Assert.True(s.GetProperty("esAdministrador").GetBoolean());
        Assert.Equal(0, await bd.EscalarAsync<int>("SELECT COUNT(*) FROM seg.Auditoria WHERE Despues LIKE '%Instalacion-2026%' OR Antes LIKE '%Instalacion-2026%'"));
    }
}
