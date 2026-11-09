using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;

namespace SMCClient.Api.Seguridad;

/// <summary>Sección "Seguridad" de appsettings.</summary>
public sealed class SeguridadOptions
{
    public const string Seccion = "Seguridad";

    /// <summary>Formulario (usuarios y contraseñas en SQL Server) o Desarrollo (sin inicio de sesión; solo en Development).</summary>
    public string Autenticacion { get; set; } = "Formulario";

    /// <summary>Usuario con el que se entra en modo Desarrollo (debe existir en seg.Usuario).</summary>
    public string UsuarioDesarrollo { get; set; } = "desarrollo";

    /// <summary>Horas de inactividad tras las que la sesión expira.</summary>
    public int HorasSesion { get; set; } = 8;

    /// <summary>Intentos de inicio de sesión por minuto desde una misma IP (además del bloqueo por cuenta en SQL).</summary>
    public int IntentosPorMinutoPorIp { get; set; } = 10;
}

public static class Politicas
{
    public const string LimiteInicioSesion = "inicio-sesion";
    public const string EncabezadoSolicitud = "X-SMC-Solicitud";
}

/// <summary>Modo Desarrollo: todos entran como Seguridad:UsuarioDesarrollo (sin sello; no cierra sesiones).</summary>
public sealed class DesarrolloAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> o, ILoggerFactory l, UrlEncoder e, IOptions<SeguridadOptions> seguridad)
    : AuthenticationHandler<AuthenticationSchemeOptions>(o, l, e)
{
    public const string Esquema = "Desarrollo";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var identidad = new ClaimsIdentity(new[] { new Claim(ClaimTypes.Name, seguridad.Value.UsuarioDesarrollo) }, Esquema);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identidad), Esquema)));
    }
}

public static class SeguridadExtensions
{
    public static IServiceCollection AddSeguridadSmc(this IServiceCollection services, IConfiguration configuracion, IHostEnvironment ambiente)
    {
        var seccion = configuracion.GetSection(SeguridadOptions.Seccion);
        services.Configure<SeguridadOptions>(seccion);
        var op = seccion.Get<SeguridadOptions>() ?? new SeguridadOptions();

        if (string.Equals(op.Autenticacion, "Desarrollo", StringComparison.OrdinalIgnoreCase))
        {
            if (!ambiente.IsDevelopment())
                throw new InvalidOperationException("Seguridad:Autenticacion = Desarrollo solo se permite en el ambiente Development.");
            services.AddAuthentication(DesarrolloAuthHandler.Esquema)
                .AddScheme<AuthenticationSchemeOptions, DesarrolloAuthHandler>(DesarrolloAuthHandler.Esquema, null);
        }
        else
        {
            services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme).AddCookie(c =>
            {
                c.Cookie.Name = "smc_sesion";
                c.Cookie.HttpOnly = true;                                   // JavaScript no la puede leer
                c.Cookie.SameSite = SameSiteMode.Strict;                    // no viaja en peticiones de otros sitios
                c.Cookie.SecurePolicy = ambiente.IsDevelopment() ? CookieSecurePolicy.SameAsRequest : CookieSecurePolicy.Always;
                c.ExpireTimeSpan = TimeSpan.FromHours(op.HorasSesion);
                c.SlidingExpiration = true;
                // Es una API: sin redirecciones a páginas de inicio de sesión.
                c.Events.OnRedirectToLogin = x => { x.Response.StatusCode = StatusCodes.Status401Unauthorized; return Task.CompletedTask; };
                c.Events.OnRedirectToAccessDenied = x => { x.Response.StatusCode = StatusCodes.Status403Forbidden; return Task.CompletedTask; };
            });
        }

        services.AddAuthorization(a => a.FallbackPolicy = new Microsoft.AspNetCore.Authorization.AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());
        services.AddMemoryCache();
        services.AddSingleton<RepositorioSesion>();
        services.AddSingleton<ServicioPermisos>();
        services.AddRateLimiter(r =>
        {
            r.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            r.AddPolicy(Politicas.LimiteInicioSesion, http =>
            {
                var limite = http.RequestServices.GetRequiredService<IOptionsMonitor<SeguridadOptions>>().CurrentValue.IntentosPorMinutoPorIp;
                return RateLimitPartition.GetFixedWindowLimiter(
                    $"{http.Connection.RemoteIpAddress?.ToString() ?? "desconocida"}:{limite}",
                    _ => new FixedWindowRateLimiterOptions { PermitLimit = limite, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 });
            });
        });
        return services;
    }

    /// <summary>
    /// Protección CSRF: toda petición que modifica (POST/PUT/DELETE) a /api debe traer el encabezado X-SMC-Solicitud.
    /// Un sitio ajeno no puede agregar encabezados propios sin permiso CORS (que la API no concede).
    /// </summary>
    public static IApplicationBuilder UseProteccionSolicitudes(this IApplicationBuilder app) => app.Use(async (http, siguiente) =>
    {
        if (!HttpMethods.IsGet(http.Request.Method) && !HttpMethods.IsHead(http.Request.Method) &&
            http.Request.Path.StartsWithSegments("/api") && !http.Request.Headers.ContainsKey(Politicas.EncabezadoSolicitud))
        {
            http.Response.StatusCode = StatusCodes.Status400BadRequest;
            await http.Response.WriteAsJsonAsync(new { title = "Falta el encabezado X-SMC-Solicitud.", status = 400, codigo = "solicitud.invalida" });
            return;
        }
        await siguiente();
    });
}
