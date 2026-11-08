using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
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
/// </summary>
[ApiController]
[Route("api/procedimientos")]
[Authorize(Policy = Politicas.Lectura)]
[Produces("application/json")]
public sealed class ProcedimientosController(
    ICatalogoProcedimientos catalogo,
    IEjecutorProcedimientos ejecutor,
    ICompuertaSincronizacion compuerta,
    IAuthorizationService autorizacion) : ControllerBase
{
    private const int SegundosReintento = 15;

    [HttpGet]
    public async Task<ActionResult<IEnumerable<ProcedimientoInfo>>> Listar(CancellationToken ct)
    {
        var procs = await catalogo.ObtenerAsync(ct);
        var visibles = new List<ProcedimientoInfo>();
        foreach (var p in procs.Values.OrderBy(p => p.Nombre, StringComparer.OrdinalIgnoreCase))
            if (await PuedeEjecutarAsync(p)) visibles.Add(p);
        return visibles;
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
            return await ejecutor.EjecutarAsync(proc, cuerpo, User.Identity?.Name ?? "desconocido", ct);
        }
        catch (ErrorProcedimientoException ex)
        {
            return Problema(ex.EstadoHttp, ex.Codigo, ex.Message, ex.Errores);
        }
    }

    private async Task<(ProcedimientoInfo? Proc, ActionResult? Error)> ResolverAsync(string nombre, CancellationToken ct)
    {
        var procs = await catalogo.ObtenerAsync(ct);
        var clave = nombre.StartsWith("api.", StringComparison.OrdinalIgnoreCase) ? nombre[4..] : nombre;
        if (!procs.TryGetValue(clave, out var proc))
            return (null, Problema(StatusCodes.Status404NotFound, "procedimiento.no_existe", $"No existe el procedimiento '{nombre}'."));
        if (!await PuedeEjecutarAsync(proc))
            return (null, Problema(StatusCodes.Status403Forbidden, "procedimiento.sin_permiso", "No tiene permiso para este procedimiento."));
        return (proc, null);
    }

    private async Task<bool> PuedeEjecutarAsync(ProcedimientoInfo p) =>
        (await autorizacion.AuthorizeAsync(User, Politicas.DePermiso(p.Permiso))).Succeeded;

    private async Task<JsonElement?> LeerCuerpoAsync(CancellationToken ct)
    {
        if (Request.ContentLength == 0) return null;
        using var lector = new StreamReader(Request.Body);
        var texto = await lector.ReadToEndAsync(ct);
        if (string.IsNullOrWhiteSpace(texto)) return null;
        using var doc = JsonDocument.Parse(texto);
        return doc.RootElement.Clone();
    }

    private ObjectResult Problema(int estado, string codigo, string titulo, IDictionary<string, string[]>? errores = null,
                                  IDictionary<string, object?>? extensiones = null)
    {
        ProblemDetails pd = errores is { Count: > 0 } ? new ValidationProblemDetails(errores) : new ProblemDetails();
        pd.Status = estado;
        pd.Title = titulo;
        pd.Extensions["codigo"] = codigo;
        if (extensiones is not null) foreach (var (k, v) in extensiones) pd.Extensions[k] = v;
        return new ObjectResult(pd) { StatusCode = estado, ContentTypes = { "application/problem+json" } };
    }
}
