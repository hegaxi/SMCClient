using System.Runtime.CompilerServices;
using SMCClient.Sync.Datos;

namespace SMCClient.Sync.Extractores;

/// <summary>Catálogos que Jira devuelve como un arreglo en una sola respuesta: campos (/field) y estados (/status).</summary>
public abstract class CatalogoArregloExtractor : IExtractor
{
    public abstract string Entidad { get; }

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        using var doc = await ctx.Jira.GetAsync(ctx.Entidad.Endpoint, ct);
        var lista = doc.RootElement.EnumerateArray()
            .Select(e => (Id: Json.Texto(e, "id"), e))
            .Where(x => !string.IsNullOrEmpty(x.Id))
            .Select(x => new DocumentoJira(x.Id!, null, x.e.GetRawText()))
            .ToList();
        foreach (var bloque in lista.Chunk(Math.Max(1, ctx.Entidad.TamanoLote)))
            yield return bloque;
    }
}

public sealed class CampoExtractor : CatalogoArregloExtractor
{
    public override string Entidad => "campo";
}

public sealed class EstadoExtractor : CatalogoArregloExtractor
{
    public override string Entidad => "estado";
}

/// <summary>GET /rest/api/3/project/search (paginado con startAt / isLast).</summary>
public sealed class ProyectoExtractor : IExtractor
{
    public string Entidad => "proyecto";

    public async IAsyncEnumerable<IReadOnlyList<DocumentoJira>> ExtraerAsync(ContextoExtraccion ctx, [EnumeratorCancellation] CancellationToken ct)
    {
        var tamano = Math.Clamp(ctx.Entidad.TamanoLote, 1, 50);
        for (var inicio = 0; ; )
        {
            using var doc = await ctx.Jira.GetAsync($"{ctx.Entidad.Endpoint}?startAt={inicio}&maxResults={tamano}", ct);
            var pagina = Json.Arreglo(doc.RootElement, "values")
                .Where(p => Json.Texto(p, "id") is not null)
                .Select(p => new DocumentoJira(Json.Texto(p, "id")!, null, p.GetRawText()))
                .ToList();
            if (pagina.Count > 0) yield return pagina;
            if (pagina.Count == 0 || Json.Booleano(doc.RootElement, "isLast") != false) yield break;
            inicio += pagina.Count;
        }
    }
}
