using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using SMCClient.Api.Procedimientos;
using SMCClient.Api.Seguridad;

namespace SMCClient.Api.Controllers;

/// <summary>
/// Sesión: iniciar, cerrar y cambiar contraseña. Es lo único que no pasa por un procedimiento del esquema api,
/// porque aquí se calcula el hash de la contraseña (para que no llegue en claro a la base) y se emite la cookie.
/// Las reglas (bloqueo, longitud, quién restablece a quién) las decide SQL Server en los procedimientos seg.*.
/// </summary>
[ApiController]
[Route("api/sesion")]
[Produces("application/json")]
public sealed class SesionController(RepositorioSesion repo, ServicioPermisos permisos, IOptions<SeguridadOptions> seguridad) : ControllerBase
{
    private const string MensajeRechazo = "Usuario o contraseña incorrectos, o la cuenta está bloqueada temporalmente por demasiados intentos.";

    public sealed record SolicitudInicio(string? Usuario, string? Contrasena);
    public sealed record SolicitudCambio(string? Actual, string? Nueva);
    public sealed record SolicitudRestablecer(string? Usuario, string? ContrasenaTemporal);
    public sealed record Sesion(string Usuario, string Nombre, string? Roles, bool EsAdministrador, bool DebeCambiarContrasena);

    private bool ModoFormulario => !string.Equals(seguridad.Value.Autenticacion, "Desarrollo", StringComparison.OrdinalIgnoreCase);

    /// <summary>La sesión actual (401 si no hay).</summary>
    [HttpGet]
    [AllowAnonymous]
    public async Task<ActionResult<Sesion>> Obtener(CancellationToken ct)
    {
        var login = ServicioPermisos.Login(User);
        if (login is null) return Problemas.Crear(401, "sesion.requerida", "Inicie sesión.");
        var p = await permisos.ObtenerAsync(User, ct);
        if (!p.Valido)
        {
            await CerrarCookieAsync();
            return Problemas.Crear(401, "sesion.invalida", "Su sesión terminó. Inicie sesión de nuevo.");
        }
        var datos = await repo.UsuarioAsync(login, ct);
        return new Sesion(login, datos?.Nombre ?? login, datos?.Roles, datos?.EsAdministrador ?? false, p.DebeCambiar);
    }

    [HttpPost("iniciar")]
    [AllowAnonymous]
    [EnableRateLimiting(Politicas.LimiteInicioSesion)]
    public async Task<ActionResult<Sesion>> Iniciar(SolicitudInicio solicitud, CancellationToken ct)
    {
        if (!ModoFormulario) return Problemas.Crear(404, "sesion.no_disponible", "En modo Desarrollo no se inicia sesión.");
        var login = solicitud.Usuario?.Trim();
        if (string.IsNullOrEmpty(login) || string.IsNullOrEmpty(solicitud.Contrasena))
            return Problemas.Crear(400, "sesion.datos", "Escriba su usuario y contraseña.");

        var credencial = await repo.CredencialAsync(login, ct);
        var coincide = Contrasenas.Verificar(solicitud.Contrasena, credencial);
        var r = await repo.RegistrarInicioAsync(login, coincide, HttpContext.Connection.RemoteIpAddress?.ToString(), ct);
        if (r.Resultado != "ok" || r.Sello is null)
            return Problemas.Crear(401, "sesion.rechazada", MensajeRechazo);

        await EmitirCookieAsync(login, r.Sello.Value);
        var datos = await repo.UsuarioAsync(login, ct);
        return new Sesion(login, r.Nombre ?? login, datos?.Roles, datos?.EsAdministrador ?? false, r.DebeCambiar);
    }

    [HttpPost("cerrar")]
    [AllowAnonymous]
    public async Task<IActionResult> Cerrar()
    {
        await CerrarCookieAsync();
        return NoContent();
    }

    /// <summary>Cambiar la propia contraseña (también la obligatoria después de un restablecimiento).</summary>
    [HttpPost("cambiar-contrasena")]
    public async Task<IActionResult> CambiarContrasena(SolicitudCambio solicitud, CancellationToken ct)
    {
        var login = ServicioPermisos.Login(User)!;
        if (string.IsNullOrEmpty(solicitud.Actual) || string.IsNullOrEmpty(solicitud.Nueva))
            return Problemas.Crear(400, "contrasena.datos", "Escriba la contraseña actual y la nueva.");

        var credencial = await repo.CredencialAsync(login, ct);
        if (!Contrasenas.Verificar(solicitud.Actual, credencial))
        {
            await repo.RegistrarInicioAsync(login, false, HttpContext.Connection.RemoteIpAddress?.ToString(), ct);   // cuenta para el bloqueo
            return Problemas.Crear(400, "contrasena.actual_incorrecta", "La contraseña actual no es correcta.",
                new Dictionary<string, string[]> { ["actual"] = new[] { "No es correcta." } });
        }
        try
        {
            var sello = await repo.EstablecerContrasenaAsync(login, Contrasenas.Calcular(solicitud.Nueva), solicitud.Nueva.Length, login, actualVerificada: true, ct);
            permisos.Invalidar();
            if (ModoFormulario) await EmitirCookieAsync(login, sello);   // esta sesión sigue; las demás se cierran
            return NoContent();
        }
        catch (ErrorProcedimientoException ex)
        {
            return Problemas.Crear(ex.EstadoHttp, ex.Codigo, ex.Message, new Dictionary<string, string[]> { ["nueva"] = new[] { ex.Message } });
        }
    }

    /// <summary>Un administrador asigna una contraseña temporal; el usuario deberá cambiarla al entrar.</summary>
    [HttpPost("restablecer-contrasena")]
    public async Task<IActionResult> RestablecerContrasena(SolicitudRestablecer solicitud, CancellationToken ct)
    {
        var login = ServicioPermisos.Login(User)!;
        var usuario = solicitud.Usuario?.Trim();
        if (string.IsNullOrEmpty(usuario) || string.IsNullOrEmpty(solicitud.ContrasenaTemporal))
            return Problemas.Crear(400, "contrasena.datos", "Indique el usuario y la contraseña temporal.");
        if (!(await permisos.ObtenerAsync(User, ct)).Valido)
            return Problemas.Crear(401, "sesion.invalida", "Su sesión terminó. Inicie sesión de nuevo.");
        try
        {
            await repo.EstablecerContrasenaAsync(usuario, Contrasenas.Calcular(solicitud.ContrasenaTemporal), solicitud.ContrasenaTemporal.Length,
                                                 login, actualVerificada: false, ct);
            permisos.Invalidar();
            return NoContent();
        }
        catch (ErrorProcedimientoException ex)
        {
            return Problemas.Crear(ex.EstadoHttp, ex.Codigo, ex.Message);
        }
    }

    private Task EmitirCookieAsync(string login, Guid sello)
    {
        var identidad = new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.Name, login),
            new Claim(ServicioPermisos.ClaimSello, sello.ToString()),
        }, CookieAuthenticationDefaults.AuthenticationScheme);
        return HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, new ClaimsPrincipal(identidad),
                                       new AuthenticationProperties { IsPersistent = false });
    }

    private Task CerrarCookieAsync() =>
        ModoFormulario ? HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme) : Task.CompletedTask;
}
