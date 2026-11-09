using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using SMCClient.Api.Seguridad;
using SMCClient.Pruebas;

namespace SMCClient.Api.Tests;

/// <summary>
/// Base desechable desplegada con los scripts de db/ y los datos de db/tests/010_prueba_integracion.sql, con un
/// login de SQL que SOLO tiene el rol smc_api (la API corre con permisos mínimos) y usuarios de la aplicación
/// con contraseña: admin (Administrador), lector y ana (Consulta). Las pruebas inician sesión de verdad (cookie).
/// </summary>
public sealed class ApiFixture : BaseDatosPrueba
{
    public const string Clave = "Clave-de-prueba-123";
    private WebApplicationFactory<Program>? _fabrica;
    private string LoginSql => "smcapi_" + Sufijo;
    private readonly string _claveSql = "Ap1-" + Guid.NewGuid().ToString("N");

    public override async Task InitializeAsync()
    {
        if (!Activo) return;
        await base.InitializeAsync();
        await EjecutarScriptAsync(Path.Combine(RaizDb(), "tests", "010_prueba_integracion.sql"));
        await EjecutarAsync("master", $"CREATE LOGIN [{LoginSql}] WITH PASSWORD = '{_claveSql}', CHECK_POLICY = OFF;");
        await EjecutarAsync($"CREATE USER [{LoginSql}] FOR LOGIN [{LoginSql}]; ALTER ROLE smc_api ADD MEMBER [{LoginSql}];");

        await CrearAdministradorAsync("admin");
        await CrearUsuarioAsync("lector", "Consulta");
        await CrearUsuarioAsync("ana", "Consulta");

        var cadenaApi = new SqlConnectionStringBuilder(Admin) { InitialCatalog = BaseDatos, UserID = LoginSql, Password = _claveSql, IntegratedSecurity = false }.ConnectionString;
        _fabrica = new WebApplicationFactory<Program>().WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Development");
            b.ConfigureAppConfiguration((_, c) => c.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:SMCClient"] = cadenaApi,
                ["Seguridad:Autenticacion"] = "Formulario",
                ["Seguridad:IntentosPorMinutoPorIp"] = "10000",
                ["Api:SegundosCacheMetadatos"] = "0",
                ["Api:SegundosCacheEstadoSync"] = "0",
                ["Api:SegundosCachePermisos"] = "0",
            }));
            b.ConfigureLogging(l => l.SetMinimumLevel(LogLevel.Warning));
        });
    }

    /// <summary>Administrador creado igual que con el comando de instalación (solo el hash llega a SQL).</summary>
    public async Task CrearAdministradorAsync(string login)
    {
        var h = Contrasenas.Calcular(Clave);
        await EjecutarAsync(BaseDatos, "EXEC seg.Instalacion_CrearAdministrador @Login = @l, @Nombre = @l, @Hash = @h, @Sal = @s, @Iteraciones = @i, @Longitud = @n;",
            ("@l", login), ("@h", h.Hash), ("@s", h.Sal), ("@i", h.Iteraciones), ("@n", Clave.Length));
    }

    /// <summary>Usuario con roles y contraseña ya establecida (no tiene que cambiarla).</summary>
    public async Task CrearUsuarioAsync(string login, string roles, string? contrasena = null)
    {
        var h = Contrasenas.Calcular(contrasena ?? Clave);
        await EjecutarAsync(BaseDatos, """
            DECLARE @t TABLE (a nvarchar(200), b nvarchar(200), c bit, d nvarchar(400), e datetimeoffset, f datetimeoffset);
            INSERT @t EXEC api.Usuario_Guardar @Login = @l, @Nombre = @l, @Roles = @r, @UsuarioActual = N'(prueba)';
            UPDATE seg.Usuario SET ContrasenaHash = @h, ContrasenaSal = @s, ContrasenaIteraciones = @i, DebeCambiarContrasena = 0 WHERE Login = @l;
            """, ("@l", login), ("@r", roles), ("@h", h.Hash), ("@s", h.Sal), ("@i", h.Iteraciones));
    }

    /// <summary>Cliente sin sesión (con el encabezado anti-CSRF que envía la interfaz).</summary>
    public HttpClient Anonimo(bool conEncabezado = true)
    {
        var c = _fabrica!.CreateClient(new WebApplicationFactoryClientOptions { HandleCookies = true });
        if (conEncabezado) c.DefaultRequestHeaders.Add(Politicas.EncabezadoSolicitud, "1");
        return c;
    }

    public async Task<HttpResponseMessage> IniciarAsync(HttpClient c, string usuario, string contrasena = Clave) =>
        await c.PostAsJsonAsync("/api/sesion/iniciar", new { usuario, contrasena });

    /// <summary>Cliente con sesión iniciada.</summary>
    public HttpClient Cliente(string usuario = "lector", string contrasena = Clave)
    {
        var c = Anonimo();
        var r = IniciarAsync(c, usuario, contrasena).GetAwaiter().GetResult();
        if (!r.IsSuccessStatusCode) throw new InvalidOperationException($"No se pudo iniciar sesión como {usuario}: {(int)r.StatusCode}");
        return c;
    }

    public HttpClient ClienteAdmin() => Cliente("admin");

    public override async Task DisposeAsync()
    {
        if (!Activo) return;
        if (_fabrica is not null) await _fabrica.DisposeAsync();
        await base.DisposeAsync();
        await EjecutarAsync("master", $"DROP LOGIN [{LoginSql}];");
    }
}
