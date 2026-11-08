using System.Runtime.CompilerServices;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync.Extractores;

/// <summary>
/// Worklogs. La búsqueda de issues solo trae 20 por issue, así que se piden aparte:
/// incremental: GET /worklog/updated?since=... (ids) + POST /worklog/list (hasta 1000 por llamada);
/// backfill de un proyecto: GET /issue/{id}/worklog de cada issue del backfill.
/// </summary>
public sealed class WorklogExtractor : IExtractor
{
    private const int MaxPorLista = 1000;

    public string Entidad => "worklog";

    public IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, CancellationToken ct) =>
        ctx.Modo == "backfill" ? PorIssueAsync(ctx, ct) : IncrementalAsync(ctx, ct);

    private static async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> IncrementalAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var ids = new List<long>();
        var desde = ctx.Desde.ToUnixTimeMilliseconds();
        while (true)
        {
            using var doc = await ctx.Jira.GetAsync($"{ctx.Entidad.Endpoint}?since={desde}", ct);
            var antes = ids.Count;
            foreach (var v in Json.Arreglo(doc.RootElement, "values"))
                if (Json.Entero(v, "worklogId") is { } id) ids.Add(id);
            var hasta = Json.Entero(doc.RootElement, "until");
            if (Json.Booleano(doc.RootElement, "lastPage") != false || ids.Count == antes || hasta is null || hasta <= desde) break;
            desde = hasta.Value;
        }

        var lista = ctx.ParametroEntidad("lista") ?? "/rest/api/3/worklog/list";
        foreach (var bloque in ids.Distinct().Chunk(MaxPorLista))
        {
            using var doc = await ctx.Jira.PostAsync(lista, new { ids = bloque }, ct);
            var pagina = doc.RootElement.EnumerateArray().Select(Documento).OfType<DocumentoJira>().ToList();
            if (pagina.Count > 0) yield return pagina;
        }
    }

    private static async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> PorIssueAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        foreach (var issue in ctx.Issues.Todos)
        {
            var pagina = new List<DocumentoJira>();
            for (var inicio = 0; ; )
            {
                using var doc = await ctx.Jira.GetAsync($"/rest/api/3/issue/{Json.Q(issue.IssueId)}/worklog?startAt={inicio}&maxResults=5000", ct);
                var antes = pagina.Count;
                pagina.AddRange(Json.Arreglo(doc.RootElement, "worklogs").Select(Documento).OfType<DocumentoJira>());
                var total = Json.Entero(doc.RootElement, "total") ?? 0;
                inicio += pagina.Count - antes;
                if (pagina.Count == antes || inicio >= total) break;
            }
            if (pagina.Count > 0) yield return pagina;
        }
    }

    private static DocumentoJira? Documento(System.Text.Json.JsonElement w) =>
        Json.Texto(w, "id") is { } id ? new DocumentoJira(id, JiraFecha.Parse(Json.Texto(w, "updated")), w.GetRawText()) : null;
}

/// <summary>GET /rest/api/3/worklog/deleted?since=...: worklogs borrados (se marcan, no se borran).</summary>
public sealed class WorklogEliminadoExtractor : IExtractor
{
    public string Entidad => "worklog_eliminado";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var desde = ctx.Desde.ToUnixTimeMilliseconds();
        while (true)
        {
            using var doc = await ctx.Jira.GetAsync($"{ctx.Entidad.Endpoint}?since={desde}", ct);
            var pagina = Json.Arreglo(doc.RootElement, "values")
                .Where(v => Json.Entero(v, "worklogId") is not null)
                .Select(v => new DocumentoJira(Json.Entero(v, "worklogId")!.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
                                               Json.Entero(v, "updatedTime") is { } t ? JiraFecha.DesdeEpochMs(t) : null, v.GetRawText()))
                .ToList();
            if (pagina.Count > 0) yield return pagina;
            var hasta = Json.Entero(doc.RootElement, "until");
            if (Json.Booleano(doc.RootElement, "lastPage") != false || pagina.Count == 0 || hasta is null || hasta <= desde) yield break;
            desde = hasta.Value;
        }
    }
}
