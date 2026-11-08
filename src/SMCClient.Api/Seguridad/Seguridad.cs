using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace SMCClient.Api.Seguridad;

/// <summary>Sección "Seguridad" de appsettings.</summary>
public sealed class SeguridadOptions
{
    public const string Seccion = "Seguridad";

    /// <summary>Windows (intranet: IIS / Kerberos-NTLM) o Desarrollo (sin autenticación; solo en ambiente Development).</summary>
    public string Autenticacion { get; set; } = "Windows";

    /// <summary>Grupos de AD que pueden consultar. Vacío = cualquier usuario autenticado del dominio.</summary>
    public List<string> GruposLectura { get; set; } = new();

    /// <summary>Grupos de AD que pueden ejecutar procedimientos de administración (smc:permiso = admin).</summary>
    public List<string> GruposAdmin { get; set; } = new();
}

public static class Politicas
{
    public const string Lectura = "lectura";
    public const string Admin = "admin";

    /// <summary>Política que corresponde a la propiedad extendida smc:permiso. Un valor desconocido se trata como admin.</summary>
    public static string DePermiso(string permiso) => permiso == Lectura ? Lectura : Admin;
}

/// <summary>Lectura o administración. Los grupos se leen de la configuración al evaluar (se pueden cambiar sin reiniciar).</summary>
public sealed class GrupoRequirement(bool admin) : IAuthorizationRequirement
{
    public bool Admin { get; } = admin;
}

public sealed class GrupoHandler(IOptionsMonitor<SeguridadOptions> seguridad) : AuthorizationHandler<GrupoRequirement>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, GrupoRequirement req)
    {
        if (context.User.Identity?.IsAuthenticated != true) return Task.CompletedTask;
        var op = seguridad.CurrentValue;
        var permitido = req.Admin
            ? op.GruposAdmin.Any(context.User.IsInRole)
            : op.GruposLectura.Count == 0 || op.GruposLectura.Concat(op.GruposAdmin).Any(context.User.IsInRole);
        if (permitido) context.Succeed(req);
        return Task.CompletedTask;
    }
}

/// <summary>Modo Desarrollo: todos entran como "desarrollo" con todos los grupos configurados.</summary>
public sealed class DesarrolloAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> o, ILoggerFactory l, UrlEncoder e, IOptions<SeguridadOptions> seguridad)
    : AuthenticationHandler<AuthenticationSchemeOptions>(o, l, e)
{
    public const string Esquema = "Desarrollo";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var claims = new List<Claim> { new(ClaimTypes.Name, "desarrollo") };
        claims.AddRange(seguridad.Value.GruposLectura.Concat(seguridad.Value.GruposAdmin).Select(g => new Claim(ClaimTypes.Role, g)));
        var identidad = new ClaimsIdentity(claims, Esquema);
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
            // En IIS habilite "Autenticación de Windows" y deshabilite "Anónima" en el sitio.
            services.AddAuthentication(NegotiateDefaults.AuthenticationScheme).AddNegotiate();
        }

        services.AddSingleton<IAuthorizationHandler, GrupoHandler>();
        services.AddAuthorization(a =>
        {
            a.AddPolicy(Politicas.Lectura, p => p.RequireAuthenticatedUser().AddRequirements(new GrupoRequirement(admin: false)));
            a.AddPolicy(Politicas.Admin, p => p.RequireAuthenticatedUser().AddRequirements(new GrupoRequirement(admin: true)));
            a.FallbackPolicy = a.GetPolicy(Politicas.Lectura);
        });
        return services;
    }
}
