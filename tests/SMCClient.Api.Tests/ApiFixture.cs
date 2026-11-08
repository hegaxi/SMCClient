using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SMCClient.Pruebas;

namespace SMCClient.Api.Tests;

/// <summary>
/// Base desechable desplegada con los scripts de db/, con los datos de db/tests/010_prueba_integracion.sql y un
/// login que SOLO tiene el rol smc_api: la API corre con permisos mínimos, como en producción.
/// </summary>
public sealed class ApiFixture : BaseDatosPrueba
{
    private WebApplicationFactory<Program>? _fabrica;
    private string Login => "smcapi_" + Sufijo;
    private readonly string _clave = "Ap1-" + Guid.NewGuid().ToString("N");

    public override async Task InitializeAsync()
    {
        if (!Activo) return;
        await base.InitializeAsync();
        await EjecutarScriptAsync(Path.Combine(RaizDb(), "tests", "010_prueba_integracion.sql"));
        await EjecutarAsync("master", $"CREATE LOGIN [{Login}] WITH PASSWORD = '{_clave}', CHECK_POLICY = OFF;");
        await EjecutarAsync($"CREATE USER [{Login}] FOR LOGIN [{Login}]; ALTER ROLE smc_api ADD MEMBER [{Login}];");

        var cadenaApi = new SqlConnectionStringBuilder(Admin) { InitialCatalog = BaseDatos, UserID = Login, Password = _clave, IntegratedSecurity = false }.ConnectionString;
        _fabrica = new WebApplicationFactory<Program>().WithWebHostBuilder(b =>
        {
            // Negotiate (Windows) no funciona en TestServer: se usa el modo Desarrollo y encima el esquema de prueba
            // como predeterminado, que sí distingue usuarios y grupos.
            b.UseEnvironment("Development");
            b.ConfigureAppConfiguration((_, c) => c.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:SMCClient"] = cadenaApi,
                ["Seguridad:Autenticacion"] = "Desarrollo",
                ["Seguridad:GruposAdmin:0"] = "SMC-Admin",
                ["Api:SegundosCacheMetadatos"] = "0",
                ["Api:SegundosCacheEstadoSync"] = "0",
            }));
            b.ConfigureLogging(l => l.SetMinimumLevel(LogLevel.Warning));
            b.ConfigureTestServices(s => s.AddAuthentication(UsuarioPruebaHandler.Esquema)
                .AddScheme<AuthenticationSchemeOptions, UsuarioPruebaHandler>(UsuarioPruebaHandler.Esquema, null));
        });
    }

    public HttpClient Cliente(string? usuario = "DOMINIO\\lector", params string[] grupos)
    {
        var c = _fabrica!.CreateClient();
        if (usuario is not null) c.DefaultRequestHeaders.Add(UsuarioPruebaHandler.EncabezadoUsuario, usuario);
        if (grupos.Length > 0) c.DefaultRequestHeaders.Add(UsuarioPruebaHandler.EncabezadoGrupos, string.Join(",", grupos));
        return c;
    }

    public HttpClient ClienteAdmin() => Cliente("DOMINIO\\admin", "SMC-Admin");

    public override async Task DisposeAsync()
    {
        if (!Activo) return;
        if (_fabrica is not null) await _fabrica.DisposeAsync();
        await base.DisposeAsync();
        await EjecutarAsync("master", $"DROP LOGIN [{Login}];");
    }
}

/// <summary>Autenticación de prueba: el usuario y sus grupos vienen en encabezados (sustituye a Windows/Negotiate).</summary>
public sealed class UsuarioPruebaHandler(IOptionsMonitor<AuthenticationSchemeOptions> o, ILoggerFactory l, UrlEncoder e)
    : AuthenticationHandler<AuthenticationSchemeOptions>(o, l, e)
{
    public const string Esquema = "Prueba";
    public const string EncabezadoUsuario = "X-Usuario-Prueba";
    public const string EncabezadoGrupos = "X-Grupos-Prueba";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(EncabezadoUsuario, out var usuario)) return Task.FromResult(AuthenticateResult.NoResult());
        var claims = new List<Claim> { new(ClaimTypes.Name, usuario.ToString()) };
        if (Request.Headers.TryGetValue(EncabezadoGrupos, out var grupos))
            claims.AddRange(grupos.ToString().Split(',', StringSplitOptions.RemoveEmptyEntries).Select(g => new Claim(ClaimTypes.Role, g)));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity(claims, Esquema)), Esquema)));
    }
}
