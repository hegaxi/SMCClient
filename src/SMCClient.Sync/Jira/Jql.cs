using System.Globalization;
using System.Text.RegularExpressions;

namespace SMCClient.Sync.Jira;

/// <summary>Construcción de JQL. Las fechas en JQL se interpretan en la zona horaria del usuario técnico de Jira.</summary>
public static partial class Jql
{
    public static string Comillas(string valor) => "\"" + valor.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

    /// <summary>JQL solo admite minutos: se trunca hacia abajo (incluye todo el minuto).</summary>
    public static string Fecha(DateTimeOffset instante, TimeZoneInfo zonaUsuarioJira) =>
        TimeZoneInfo.ConvertTime(instante, zonaUsuarioJira).ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);

    public static string? ExcluirProyectos(IReadOnlyCollection<string> claves) =>
        claves.Count == 0 ? null : $"project not in ({string.Join(", ", claves.Select(Comillas))})";

    public static string Unir(params string?[] condiciones) =>
        string.Join(" AND ", condiciones.Where(c => !string.IsNullOrWhiteSpace(c)).Select(c => "(" + c + ")"));

    public static string Incremental(DateTimeOffset desde, TimeZoneInfo zona, IReadOnlyCollection<string> excluidos, string? jqlBase) =>
        Unir($"updated >= {Comillas(Fecha(desde, zona))}", ExcluirProyectos(excluidos), jqlBase) + " ORDER BY updated ASC";

    /// <summary>customfield_10099 -> cf[10099] is not EMPTY (backfill de un campo nuevo).</summary>
    public static string CampoNoVacio(string campoId)
    {
        var m = CampoCustom().Match(campoId);
        if (!m.Success) throw new ArgumentException($"Id de campo personalizado inválido: '{campoId}'.", nameof(campoId));
        return $"cf[{m.Groups[1].Value}] is not EMPTY";
    }

    public static string Proyecto(string clave) => $"project = {Comillas(clave)}";

    [GeneratedRegex(@"^customfield_(\d+)$")]
    private static partial Regex CampoCustom();
}
