using System.Globalization;

namespace SMCClient.Sync.Jira;

/// <summary>Fechas de Jira: '2026-07-08T09:30:36.291-0600' (zona sin ':'), '...Z' o milisegundos epoch.</summary>
public static class JiraFecha
{
    private static readonly string[] Formatos =
    {
        "yyyy-MM-dd'T'HH:mm:ss.fffzzz", "yyyy-MM-dd'T'HH:mm:sszzz", "yyyy-MM-dd'T'HH:mm:ss.fffK", "yyyy-MM-dd'T'HH:mm:ssK",
    };

    public static DateTimeOffset? Parse(string? valor)
    {
        if (string.IsNullOrWhiteSpace(valor)) return null;
        var v = valor.Trim();
        // '-0600' -> '-06:00'
        if (v.Length > 5 && (v[^5] == '+' || v[^5] == '-') && char.IsDigit(v[^4]) && char.IsDigit(v[^1]) && v.Contains('T'))
            v = v[..^2] + ":" + v[^2..];
        return DateTimeOffset.TryParseExact(v, Formatos, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var r)
            ? r
            : DateTimeOffset.TryParse(v, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out r) ? r : null;
    }

    public static DateTimeOffset DesdeEpochMs(long ms) => DateTimeOffset.FromUnixTimeMilliseconds(ms);
}
