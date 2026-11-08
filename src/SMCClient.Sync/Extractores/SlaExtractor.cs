using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Text;
using SMCClient.Sync.Datos;

namespace SMCClient.Sync.Extractores;

/// <summary>
/// GET /rest/servicedeskapi/request/{id}/sla para los tickets de mesa de ayuda que cambiaron.
/// Se usa este endpoint porque el campo SLA de la búsqueda (NEW_SLA_FORMAT) no trae el ciclo en curso.
/// Junta todas las páginas en {"values":[...]}. Si Jira responde 404/403 (no es una solicitud de JSM), se omite.
/// </summary>
public sealed class SlaExtractor : IExtractor
{
    public string Entidad => "sla";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var tipo = ctx.ParametroEntidad("soloTipoProyecto");
        var issues = ctx.Issues.Todos.Where(i => tipo is null || string.Equals(i.TipoProyecto, tipo, StringComparison.OrdinalIgnoreCase)).ToList();
        var opciones = new ParallelOptions { MaxDegreeOfParallelism = Math.Max(1, ctx.MaxConcurrencia), CancellationToken = ct };

        foreach (var bloque in issues.Chunk(Math.Max(1, ctx.Entidad.TamanoLote)))
        {
            var resultado = new ConcurrentBag<DocumentoJira>();
            await Parallel.ForEachAsync(bloque, opciones, async (issue, token) =>
            {
                if (await ObtenerAsync(ctx, issue.IssueId, token) is { } json) resultado.Add(new DocumentoJira(issue.IssueId, null, json));
            });
            if (!resultado.IsEmpty) yield return resultado.ToList();
        }
    }

    private static async Task<string?> ObtenerAsync(ContextoExtraccion ctx, string issueId, CancellationToken ct)
    {
        var ruta = ctx.Entidad.Endpoint.Replace("{issueIdOrKey}", Json.Q(issueId), StringComparison.Ordinal);
        var valores = new List<string>();
        for (var inicio = 0; ; )
        {
            using var doc = await ctx.Jira.GetOpcionalAsync($"{ruta}?start={inicio}&limit=50", ct);
            if (doc is null) return inicio == 0 ? null : Documento(valores);
            var antes = valores.Count;
            valores.AddRange(Json.Arreglo(doc.RootElement, "values").Select(v => v.GetRawText()));
            inicio += valores.Count - antes;
            if (Json.Booleano(doc.RootElement, "isLastPage") != false || valores.Count == antes) break;
        }
        return Documento(valores);
    }

    private static string Documento(List<string> valores) => new StringBuilder("{\"values\":[").AppendJoin(',', valores).Append("]}").ToString();
}
