using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using SMCClient.Sync.Datos;

namespace SMCClient.Sync.Extractores;

/// <summary>
/// POST /rest/api/3/changelog/bulkfetch para los issues que cambiaron en la corrida.
/// Junta todas las páginas y entrega un documento por issue con su historial completo:
/// {"issueId":"...","histories":[...]}.
/// </summary>
public sealed class ChangelogExtractor : IExtractor
{
    public string Entidad => "changelog";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var tamano = Math.Clamp(ctx.Entidad.TamanoLote, 1, 1000);
        foreach (var bloque in ctx.Issues.Todos.Select(i => i.IssueId).Chunk(tamano))
        {
            var historias = bloque.ToDictionary(id => id, _ => new List<string>(), StringComparer.Ordinal);
            // bulkfetch puede repetir una historia entre páginas: se guarda una sola vez por id.
            var vistas = new HashSet<string>(StringComparer.Ordinal);
            string? token = null;
            do
            {
                using var doc = await ctx.Jira.PostAsync(ctx.Entidad.Endpoint,
                    new { issueIdsOrKeys = bloque, maxResults = 1000, nextPageToken = token }, ct);
                foreach (var registro in Json.Arreglo(doc.RootElement, "issueChangeLogs"))
                {
                    var id = Json.Texto(registro, "issueId");
                    if (id is null || !historias.TryGetValue(id, out var lista)) continue;
                    foreach (var h in Json.Arreglo(registro, "changeHistories"))
                    {
                        var hid = Json.Texto(h, "id");
                        if (hid is null || vistas.Add(hid)) lista.Add(h.GetRawText());
                    }
                }
                token = Json.Texto(doc.RootElement, "nextPageToken");
            } while (token is not null);

            yield return historias.Select(kv => new DocumentoJira(kv.Key, null, Documento(kv.Key, kv.Value))).ToList();
        }
    }

    private static string Documento(string issueId, List<string> historias)
    {
        var sb = new StringBuilder("{\"issueId\":").Append(JsonSerializer.Serialize(issueId)).Append(",\"histories\":[");
        sb.AppendJoin(',', historias);
        return sb.Append("]}").ToString();
    }
}
