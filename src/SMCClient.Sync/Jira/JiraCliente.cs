using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace SMCClient.Sync.Jira;

public interface IJiraCliente
{
    Task<JsonDocument> GetAsync(string ruta, CancellationToken ct);

    /// <summary>Igual que GetAsync, pero devuelve null si Jira responde 404 o 403 (p. ej. SLA de un issue que no es de JSM).</summary>
    Task<JsonDocument?> GetOpcionalAsync(string ruta, CancellationToken ct);

    Task<JsonDocument> PostAsync(string ruta, object cuerpo, CancellationToken ct);

    /// <summary>Zona horaria del usuario técnico (Jira interpreta las fechas del JQL en esa zona).</summary>
    Task<TimeZoneInfo> ObtenerZonaHorariaAsync(CancellationToken ct);
}

public sealed class JiraException(HttpStatusCode estado, string ruta, string detalle)
    : Exception($"Jira respondió {(int)estado} {estado} en {ruta}: {detalle}")
{
    public HttpStatusCode Estado { get; } = estado;
}

/// <summary>
/// Cliente HTTP de Jira. Los reintentos (429 respetando Retry-After, 5xx, timeouts) y el circuit breaker
/// los aplica el AddStandardResilienceHandler configurado en AddSmcSync.
/// </summary>
public sealed class JiraCliente(HttpClient http, ILogger<JiraCliente> log) : IJiraCliente
{
    private static readonly JsonSerializerOptions OpcionesJson = new() { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };
    private TimeZoneInfo? _zona;

    public async Task<JsonDocument> GetAsync(string ruta, CancellationToken ct) =>
        await GetOpcionalAsync(ruta, ct, opcional: false) ?? throw new InvalidOperationException("Respuesta vacía.");

    public Task<JsonDocument?> GetOpcionalAsync(string ruta, CancellationToken ct) => GetOpcionalAsync(ruta, ct, opcional: true);

    public async Task<JsonDocument> PostAsync(string ruta, object cuerpo, CancellationToken ct)
    {
        using var respuesta = await http.PostAsJsonAsync(ruta, cuerpo, OpcionesJson, ct);
        await AsegurarExitoAsync(respuesta, ruta, ct);
        return await LeerAsync(respuesta, ct);
    }

    public async Task<TimeZoneInfo> ObtenerZonaHorariaAsync(CancellationToken ct)
    {
        if (_zona is not null) return _zona;
        using var yo = await GetAsync("/rest/api/3/myself", ct);
        var id = yo.RootElement.TryGetProperty("timeZone", out var tz) ? tz.GetString() : null;
        try
        {
            _zona = id is null ? TimeZoneInfo.Utc : TimeZoneInfo.FindSystemTimeZoneById(id);
        }
        catch (TimeZoneNotFoundException)
        {
            log.LogWarning("Zona horaria de Jira '{Zona}' desconocida en este servidor; se usa UTC.", id);
            _zona = TimeZoneInfo.Utc;
        }
        return _zona;
    }

    private async Task<JsonDocument?> GetOpcionalAsync(string ruta, CancellationToken ct, bool opcional)
    {
        using var respuesta = await http.GetAsync(ruta, HttpCompletionOption.ResponseHeadersRead, ct);
        if (opcional && respuesta.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.Forbidden) return null;
        await AsegurarExitoAsync(respuesta, ruta, ct);
        return await LeerAsync(respuesta, ct);
    }

    private static async Task<JsonDocument> LeerAsync(HttpResponseMessage respuesta, CancellationToken ct)
    {
        await using var s = await respuesta.Content.ReadAsStreamAsync(ct);
        return await JsonDocument.ParseAsync(s, cancellationToken: ct);
    }

    private static async Task AsegurarExitoAsync(HttpResponseMessage respuesta, string ruta, CancellationToken ct)
    {
        if (respuesta.IsSuccessStatusCode) return;
        var cuerpo = await respuesta.Content.ReadAsStringAsync(ct);
        throw new JiraException(respuesta.StatusCode, ruta.Split('?')[0], cuerpo.Length > 500 ? cuerpo[..500] : cuerpo);
    }
}

public interface IJiraClienteFactory
{
    IJiraCliente Crear(string codigoFuente);
}

public sealed class JiraClienteFactory(IHttpClientFactory http, ILoggerFactory logs) : IJiraClienteFactory
{
    public static string NombreCliente(string codigoFuente) => "jira:" + codigoFuente;

    public IJiraCliente Crear(string codigoFuente) =>
        new JiraCliente(http.CreateClient(NombreCliente(codigoFuente)), logs.CreateLogger<JiraCliente>());
}
