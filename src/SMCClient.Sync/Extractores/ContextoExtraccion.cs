using System.Collections.Concurrent;
using System.Text.Json;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync.Extractores;

/// <summary>Issues vistos en la corrida: los usan las entidades dependientes (changelog, SLA).</summary>
public sealed class IssuesCambiados
{
    private readonly ConcurrentDictionary<string, IssueCambiado> _issues = new();

    public void Agregar(IssueCambiado issue) => _issues[issue.IssueId] = issue;

    public IReadOnlyList<IssueCambiado> Todos => _issues.Values.OrderBy(i => i.IssueId, StringComparer.Ordinal).ToList();

    public int Cantidad => _issues.Count;
}

public sealed record IssueCambiado(string IssueId, string Clave, string? TipoProyecto);

public sealed class ContextoExtraccion
{
    public required ConfiguracionFuente Fuente { get; init; }
    public required EntidadConfig Entidad { get; init; }
    public required IJiraCliente Jira { get; init; }

    /// <summary>inicial | incremental | catalogo | backfill</summary>
    public required string Modo { get; init; }

    /// <summary>Desde qué fecha pedir cambios (marca de agua menos traslape).</summary>
    public DateTimeOffset Desde { get; init; }

    /// <summary>Parámetros de una solicitud de backfill: {"campoId":"customfield_10099"} o {"proyecto":"SMC26"}.</summary>
    public JsonElement? ParametrosSolicitud { get; init; }

    public required IssuesCambiados Issues { get; init; }

    public int MaxConcurrencia { get; init; } = 4;

    public string? ParametroEntidad(string nombre)
    {
        if (string.IsNullOrWhiteSpace(Entidad.Parametros)) return null;
        using var doc = JsonDocument.Parse(Entidad.Parametros);
        return doc.RootElement.TryGetProperty(nombre, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    }

    public string? ParametroSolicitud(string nombre) =>
        ParametrosSolicitud is { ValueKind: JsonValueKind.Object } p && p.TryGetProperty(nombre, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() : null;
}

/// <summary>Trae de Jira los documentos de una entidad, página por página.</summary>
public interface IExtractor
{
    string Entidad { get; }
    IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, CancellationToken ct);
}

internal static class Json
{
    public static string? Texto(JsonElement e, string propiedad) =>
        e.TryGetProperty(propiedad, out var v) ? v.ValueKind switch
        {
            JsonValueKind.String => v.GetString(),
            JsonValueKind.Number => v.GetRawText(),
            _ => null,
        } : null;

    public static bool? Booleano(JsonElement e, string propiedad) =>
        e.TryGetProperty(propiedad, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False ? v.GetBoolean() : null;

    public static long? Entero(JsonElement e, string propiedad) =>
        e.TryGetProperty(propiedad, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n) ? n : null;

    public static IEnumerable<JsonElement> Arreglo(JsonElement e, string propiedad) =>
        e.TryGetProperty(propiedad, out var v) && v.ValueKind == JsonValueKind.Array ? v.EnumerateArray() : Enumerable.Empty<JsonElement>();

    public static string Q(string valor) => Uri.EscapeDataString(valor);
}
