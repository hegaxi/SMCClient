using System.Runtime.CompilerServices;
using System.Text.Json;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync.Extractores;

/// <summary>
/// GET /rest/api/3/search/jql (paginado con nextPageToken) con fields=*all.
/// Incremental: updated >= marca de agua, sin proyectos excluidos.
/// Backfill: cf[N] is not EMPTY (campo nuevo) o project = X (proyecto que se vuelve a incluir).
/// Padres: claves de padres o épicas faltantes (sync.Padres_Pendientes), por /rest/api/3/issue/bulkfetch.
/// </summary>
public sealed class IssueExtractor : IExtractor
{
    public string Entidad => "issue";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var campos = ctx.ParametroEntidad("fields") ?? "*all";
        if (ctx.Modo == "padres")
        {
            // Padres o épicas faltantes, por clave: POST /rest/api/3/issue/bulkfetch (hasta 100 por llamada). Las claves que
            // Jira ya no tiene llegan en issueErrors y se ignoran (la base las reintenta una vez al día).
            var claves = ctx.ParametrosSolicitud is { ValueKind: JsonValueKind.Object } p && p.TryGetProperty("claves", out var arr)
                ? arr.EnumerateArray().Select(c => c.GetString()).OfType<string>().ToList() : new List<string>();
            var endpoint = ctx.ParametroEntidad("bulkfetch") ?? "/rest/api/3/issue/bulkfetch";
            foreach (var bloque in claves.Chunk(100))
            {
                using var doc = await ctx.Jira.PostAsync(endpoint, new { issueIdsOrKeys = bloque, fields = new[] { campos } }, ct);
                var pagina = Pagina(ctx, doc.RootElement);
                if (pagina.Count > 0) yield return pagina;
            }
            yield break;
        }

        var jql = await ConstruirJqlAsync(ctx, ct);
        var tamano = Math.Clamp(ctx.Entidad.TamanoLote, 1, 100);
        string? token = null;
        do
        {
            var url = $"{ctx.Entidad.Endpoint}?jql={Json.Q(jql)}&fields={Json.Q(campos)}&maxResults={tamano}"
                      + (token is null ? "" : $"&nextPageToken={Json.Q(token)}");
            using var doc = await ctx.Jira.GetAsync(url, ct);
            var pagina = Pagina(ctx, doc.RootElement);
            if (pagina.Count > 0) yield return pagina;

            token = Json.Texto(doc.RootElement, "nextPageToken");
            if (Json.Booleano(doc.RootElement, "isLast") == true) token = null;
        } while (token is not null);
    }

    /// <summary>Documentos de una respuesta con "issues" (búsqueda o bulkfetch; misma forma).</summary>
    private static List<DocumentoJira> Pagina(ContextoExtraccion ctx, JsonElement raiz)
    {
        var pagina = new List<DocumentoJira>();
        foreach (var issue in Json.Arreglo(raiz, "issues"))
        {
            var id = Json.Texto(issue, "id");
            if (id is null) continue;
            var clave = Json.Texto(issue, "key") ?? id;
            string? actualizado = null, tipoProyecto = null, claveProyecto = null;
            if (issue.TryGetProperty("fields", out var f))
            {
                actualizado = Json.Texto(f, "updated");
                if (f.TryGetProperty("project", out var p) && p.ValueKind == JsonValueKind.Object)
                {
                    tipoProyecto = Json.Texto(p, "projectTypeKey");
                    claveProyecto = Json.Texto(p, "key");
                }
            }
            // Los issues de proyectos excluidos (si llegan) no generan peticiones de worklogs; la base tampoco los integra.
            if (claveProyecto is null || !ctx.Fuente.ProyectosExcluidos.Contains(claveProyecto, StringComparer.OrdinalIgnoreCase))
                ctx.Issues.Agregar(new IssueCambiado(id, clave, tipoProyecto));
            pagina.Add(new DocumentoJira(id, JiraFecha.Parse(actualizado), issue.GetRawText()));
        }
        return pagina;
    }

    internal static async Task<string> ConstruirJqlAsync(ContextoExtraccion ctx, CancellationToken ct)
    {
        var excluidos = Jql.ExcluirProyectos(ctx.Fuente.ProyectosExcluidos);
        if (ctx.Modo == "backfill")
        {
            if (ctx.ParametroSolicitud("campoId") is { } campo)
                return Jql.Unir(Jql.CampoNoVacio(campo), excluidos) + " ORDER BY updated ASC";
            if (ctx.ParametroSolicitud("proyecto") is { } proyecto)
                return Jql.Proyecto(proyecto) + " ORDER BY updated ASC";
            throw new InvalidOperationException("Backfill sin 'campoId' ni 'proyecto'.");
        }
        var zona = await ctx.Jira.ObtenerZonaHorariaAsync(ct);
        return Jql.Incremental(ctx.Desde, zona, ctx.Fuente.ProyectosExcluidos, ctx.ParametroEntidad("jqlBase"));
    }
}
