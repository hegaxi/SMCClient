using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using SMCClient.Sync.Datos;

namespace SMCClient.Sync.Extractores;

/// <summary>
/// GET /rest/api/2/issue/{id}/comment (v2: el cuerpo llega como texto, no como documento ADF) para los issues pendientes.
/// Junta todas las páginas en un documento por issue: {"issueId":"...","comments":[...]}. Cada comentario trae jsdPublic
/// en mesa de ayuda (público para el cliente o nota interna). Si Jira responde 404/403 (issue borrado), se omite.
/// </summary>
public sealed class ComentarioExtractor : IExtractor
{
    public string Entidad => "comentario";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var opciones = new ParallelOptions { MaxDegreeOfParallelism = Math.Max(1, ctx.MaxConcurrencia), CancellationToken = ct };
        foreach (var bloque in ctx.Issues.Todos.Chunk(Math.Max(1, ctx.Entidad.TamanoLote)))
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
        var comentarios = new List<string>();
        for (var inicio = 0; ; )
        {
            using var doc = await ctx.Jira.GetOpcionalAsync($"{ruta}?startAt={inicio}&maxResults=100&orderBy=created", ct);
            if (doc is null) return inicio == 0 ? null : Documento(issueId, comentarios);
            var antes = comentarios.Count;
            comentarios.AddRange(Json.Arreglo(doc.RootElement, "comments").Select(c => c.GetRawText()));
            inicio += comentarios.Count - antes;
            var total = Json.Entero(doc.RootElement, "total") ?? comentarios.Count;
            if (comentarios.Count == antes || comentarios.Count >= total) break;
        }
        return Documento(issueId, comentarios);
    }

    private static string Documento(string issueId, List<string> comentarios) =>
        new StringBuilder("{\"issueId\":").Append(JsonSerializer.Serialize(issueId)).Append(",\"comments\":[")
            .AppendJoin(',', comentarios).Append("]}").ToString();
}
