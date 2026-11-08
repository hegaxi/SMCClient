using System.Security.Claims;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using SMCClient.Api.Procedimientos;

namespace SMCClient.Api.Seguridad;

/// <summary>
/// Permisos del usuario de la sesión, decididos por seg.Permisos_Usuario. Se guardan unos segundos en memoria
/// (Api:SegundosCachePermisos) y se descartan después de cualquier acción (smc:accion), así un cambio de
/// roles hecho desde la aplicación se ve de inmediato.
/// </summary>
public sealed class ServicioPermisos(RepositorioSesion repo, IMemoryCache cache, IOptions<ApiOptions> opciones)
{
    public const string ClaimSello = "smc:sello";
    private CancellationTokenSource _version = new();

    public static string? Login(ClaimsPrincipal usuario) => usuario.Identity?.IsAuthenticated == true ? usuario.Identity.Name : null;

    public static Guid? Sello(ClaimsPrincipal usuario) =>
        Guid.TryParse(usuario.FindFirstValue(ClaimSello), out var g) ? g : null;

    public async Task<PermisosUsuario> ObtenerAsync(ClaimsPrincipal usuario, CancellationToken ct)
    {
        var login = Login(usuario);
        if (login is null) return new PermisosUsuario(false, false, new HashSet<string>());
        var sello = Sello(usuario);
        var clave = $"permisos:{login}:{sello}";
        if (cache.TryGetValue(clave, out PermisosUsuario? guardado)) return guardado!;

        var permisos = await repo.PermisosAsync(login, sello, ct);
        var segundos = opciones.Value.SegundosCachePermisos;
        if (segundos > 0)
            cache.Set(clave, permisos, new MemoryCacheEntryOptions()
                .SetAbsoluteExpiration(TimeSpan.FromSeconds(segundos))
                .AddExpirationToken(new Microsoft.Extensions.Primitives.CancellationChangeToken(_version.Token)));
        return permisos;
    }

    /// <summary>Descarta todos los permisos guardados (después de administrar usuarios o roles).</summary>
    public void Invalidar()
    {
        var anterior = Interlocked.Exchange(ref _version, new CancellationTokenSource());
        anterior.Cancel();
        anterior.Dispose();
    }
}
