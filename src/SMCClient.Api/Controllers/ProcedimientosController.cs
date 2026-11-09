using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Mvc;
using SMCClient.Api.Procedimientos;
using SMCClient.Api.Seguridad;
using SMCClient.Api.Sincronizacion;

namespace SMCClient.Api.Controllers;

/// <summary>
/// ÚNICO controlador de la aplicación. Descubre los procedimientos del esquema api en la base y los ejecuta.
/// Un procedimiento nuevo en la base aparece aquí sin tocar este código.
///   GET  /api/procedimientos            lista los procedimientos que el usuario puede ejecutar (con parámetros y columnas)
///   GET  /api/procedimientos/{nombre}   metadatos de uno
///   POST /api/procedimientos/{nombre}   lo ejecuta; cuerpo: {"Proyecto":"SMC26","Pagina":1}
/// Antes de ejecutar, si los datos de Jira no están sincronizados responde 503 (salvo procedimientos smc:exentoSync = 1).
/// Qué puede ejecutar cada usuario lo decide SQL Server (seg.Permisos_Usuario).
/// </summary>
[ApiController]
[Route("api/procedimientos")]
[Produces("application/json")]
public sealed class ProcedimientosController(
    ICatalogoProcedimientos catalogo,
    IEjecutorProcedimientos ejecutor,
    ICompuertaSincronizacion compuerta,
    ServicioPermisos permisos) : ControllerBase
{
    private const int SegundosReintento = 15;

    [HttpGet]
    public async Task<ActionResult<IEnumerable<ProcedimientoInfo>>> Listar(CancellationToken ct)
    {
        var (permitidos, error) = await PermisosAsync(ct);
        if (error is not null) return error;
        var procs = await catalogo.ObtenerAsync(ct);
        return procs.Values.Where(p => permitidos!.Contains(p.Nombre)).OrderBy(p => p.Nombre, StringComparer.OrdinalIgnoreCase).ToList();
    }

    [HttpGet("{nombre}")]
    public async Task<ActionResult<ProcedimientoInfo>> Obtener(string nombre, CancellationToken ct)
    {
        var (proc, error) = await ResolverAsync(nombre, ct);
        return proc is null ? error! : proc;
    }

    [HttpPost("{nombre}")]
    public async Task<ActionResult<ResultadoEjecucion>> Ejecutar(string nombre, CancellationToken ct)
    {
        var (proc, error) = await ResolverAsync(nombre, ct);
        if (proc is null) return error!;

        if (!proc.ExentoSync)
        {
            var pendientes = await compuerta.FuentesPendientesAsync(ct);
            if (pendientes.Count > 0)
            {
                Response.Headers.RetryAfter = SegundosReintento.ToString(System.Globalization.CultureInfo.InvariantCulture);
                return Problema(StatusCodes.Status503ServiceUnavailable, "sync.pendiente",
                    "Los datos de Jira se están sincronizando. Intente de nuevo en unos segundos.",
                    extensiones: new Dictionary<string, object?> { ["fuentes"] = pendientes });
            }
        }

        JsonElement? cuerpo;
        try
        {
            cuerpo = await LeerCuerpoAsync(ct);
        }
        catch (JsonException)
        {
            return Problema(StatusCodes.Status400BadRequest, "cuerpo.invalido", "El cuerpo no es JSON válido.");
        }

        try
        {
            var resultado = await ejecutor.EjecutarAsync(proc, cuerpo, User.Identity!.Name!, ct);
            if (proc.Accion) permisos.Invalidar();   // p. ej. cambió los roles de alguien
            return resultado;
        }
        catch (ErrorProcedimientoException ex)
        {
            return Problema(ex.EstadoHttp, ex.Codigo, ex.Message, ex.Errores);
        }
    }

    /// <summary>Procedimientos permitidos según SQL Server, o el error de sesión correspondiente.</summary>
    private async Task<(IReadOnlySet<string>? Permitidos, ActionResult? Error)> PermisosAsync(CancellationToken ct)
    {
        var p = await permisos.ObtenerAsync(User, ct);
        if (!p.Valido)
        {
            if (User.Identity?.AuthenticationType == CookieAuthenticationDefaults.AuthenticationScheme)
                await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return (null, Problema(StatusCodes.Status401Unauthorized, "sesion.invalida", "Su sesión terminó. Inicie sesión de nuevo."));
        }
        if (p.DebeCambiar)
            return (null, Problema(StatusCodes.Status403Forbidden, "contrasena.debe_cambiar", "Debe cambiar su contraseña antes de continuar."));
        if (p.Procedimientos.Count == 0)
            return (null, Problema(StatusCodes.Status403Forbidden, "usuario.sin_acceso", "Su usuario no tiene permisos. Pida a un administrador que le asigne un rol."));
        return (p.Procedimientos, null);
    }

    private async Task<(ProcedimientoInfo? Proc, ActionResult? Error)> ResolverAsync(string nombre, CancellationToken ct)
    {
        var (permitidos, error) = await PermisosAsync(ct);
        if (error is not null) return (null, error);
        var procs = await catalogo.ObtenerAsync(ct);
        var clave = nombre.StartsWith("api.", StringComparison.OrdinalIgnoreCase) ? nombre[4..] : nombre;
        if (!procs.TryGetValue(clave, out var proc))
            return (null, Problema(StatusCodes.Status404NotFound, "procedimiento.no_existe", $"No existe el procedimiento '{nombre}'."));
        if (!permitidos!.Contains(proc.Nombre))
            return (null, Problema(StatusCodes.Status403Forbidden, "procedimiento.sin_permiso", "No tiene permiso para este procedimiento."));
        return (proc, null);
    }

    private async Task<JsonElement?> LeerCuerpoAsync(CancellationToken ct)
    {
        if (Request.ContentLength == 0) return null;
        using var lector = new StreamReader(Request.Body);
        var texto = await lector.ReadToEndAsync(ct);
        if (string.IsNullOrWhiteSpace(texto)) return null;
        using var doc = JsonDocument.Parse(texto);
        return doc.RootElement.Clone();
    }

    private static ObjectResult Problema(int estado, string codigo, string titulo, IDictionary<string, string[]>? errores = null,
                                         IDictionary<string, object?>? extensiones = null) =>
        Problemas.Crear(estado, codigo, titulo, errores, extensiones);
}
