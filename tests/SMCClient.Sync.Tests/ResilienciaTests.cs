using System.Net;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using SMCClient.Sync.Jira;
using Xunit;

namespace SMCClient.Sync.Tests;

/// <summary>Verifica la configuración real de AddSmcSync: autenticación y reintento ante 429 con Retry-After.</summary>
public class ResilienciaTests
{
    [Fact]
    public async Task Reintenta_un_429_respetando_RetryAfter_y_envia_autenticacion_basic()
    {
        var llamadas = 0;
        string? autorizacion = null;
        var jira = new FakeJira().Responder((_, url) => url == "/rest/api/3/myself", (r, _) =>
        {
            autorizacion = r.Headers.Authorization?.ToString();
            if (Interlocked.Increment(ref llamadas) == 1)
            {
                var limite = new HttpResponseMessage(HttpStatusCode.TooManyRequests) { Content = new StringContent("{}") };
                limite.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(1));
                return limite;
            }
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("""{"timeZone":"UTC"}""", Encoding.UTF8, "application/json") };
        });

        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:SMCClient"] = "Server=.;Database=x;Integrated Security=true",
            ["SmcSync:Fuentes:0:Codigo"] = "smco",
            ["SmcSync:Fuentes:0:UrlBase"] = "https://smco.atlassian.net",
            ["SmcSync:Fuentes:0:Usuario"] = "tecnico@ejemplo.test",
            ["SmcSync:Fuentes:0:Token"] = "token-de-prueba",
        }).Build();
        var services = new ServiceCollection().AddLogging();
        services.AddSmcSync(config, hospedarWorker: false);
        services.AddHttpClient(JiraClienteFactory.NombreCliente("smco")).ConfigurePrimaryHttpMessageHandler(() => jira);
        await using var sp = services.BuildServiceProvider();

        using var doc = await sp.GetRequiredService<IJiraClienteFactory>().Crear("smco").GetAsync("/rest/api/3/myself", CancellationToken.None);

        Assert.Equal(2, llamadas);
        Assert.Equal("Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes("tecnico@ejemplo.test:token-de-prueba")), autorizacion);
    }

    [Fact]
    public void Sin_token_la_configuracion_falla_al_arrancar()
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:SMCClient"] = "Server=.;Database=x;Integrated Security=true",
            ["SmcSync:Fuentes:0:Codigo"] = "smco",
            ["SmcSync:Fuentes:0:UrlBase"] = "https://smco.atlassian.net",
        }).Build();
        var services = new ServiceCollection().AddLogging();
        services.AddSmcSync(config, hospedarWorker: false);
        using var sp = services.BuildServiceProvider();

        var ex = Assert.Throws<Microsoft.Extensions.Options.OptionsValidationException>(
            () => sp.GetRequiredService<Microsoft.Extensions.Options.IOptions<SMCClient.Sync.Configuracion.SmcSyncOptions>>().Value);
        Assert.Contains("token", ex.Message, StringComparison.OrdinalIgnoreCase);
    }
}
