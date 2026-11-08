using System.Runtime.CompilerServices;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync.Extractores;

/// <summary>
/// GET /rest/api/3/search/jql (paginado con nextPageToken) con fields=*all.
/// Incremental: updated >= marca de agua, sin proyectos excluidos.
/// Backfill: cf[N] is not EMPTY (campo nuevo) o project = X (proyecto que se vuelve a incluir).
/// </summary>
public sealed class IssueExtractor : IExtractor
{
    public string Entidad => "issue";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var jql = await ConstruirJqlAsync(ctx, ct);
        var campos = ctx.ParametroEntidad("fields") ?? "*all";
        var tamano = Math.Clamp(ctx.Entidad.TamanoLote, 1, 100);
        string? token = null;
        do
        {
            var url = $"{ctx.Entidad.Endpoint}?jql={Json.Q(jql)}&fields={Json.Q(campos)}&maxResults={tamano}"
                      + (token is null ? "" : $"&nextPageToken={Json.Q(token)}");
            using var doc = await ctx.Jira.GetAsync(url, ct);
            var pagina = new List<DocumentoJira>();
            foreach (var issue in Json.Arreglo(doc.RootElement, "issues"))
            {
                var id = Json.Texto(issue, "id");
                if (id is null) continue;
                var clave = Json.Texto(issue, "key") ?? id;
                string? actualizado = null, tipoProyecto = null, claveProyecto = null;
                if (issue.TryGetProperty("fields", out var f))
                {
                    actualizado = Json.Texto(f, "updated");
                    if (f.TryGetProperty("project", out var p) && p.ValueKind == System.Text.Json.JsonValueKind.Object)
                    {
                        tipoProyecto = Json.Texto(p, "projectTypeKey");
                        claveProyecto = Json.Texto(p, "key");
                    }
                }
                // Los issues de proyectos excluidos (si llegan) no generan peticiones de changelog, worklogs ni SLA;
                // la base tampoco los integra.
                if (claveProyecto is null || !ctx.Fuente.ProyectosExcluidos.Contains(claveProyecto, StringComparer.OrdinalIgnoreCase))
                    ctx.Issues.Agregar(new IssueCambiado(id, clave, tipoProyecto));
                pagina.Add(new DocumentoJira(id, JiraFecha.Parse(actualizado), issue.GetRawText()));
            }
            if (pagina.Count > 0) yield return pagina;

            token = Json.Texto(doc.RootElement, "nextPageToken");
            if (Json.Booleano(doc.RootElement, "isLast") == true) token = null;
        } while (token is not null);
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
