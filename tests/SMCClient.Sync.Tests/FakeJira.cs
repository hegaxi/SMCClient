using System.Collections.Concurrent;
using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync.Tests;

/// <summary>Jira simulado: rutas registradas con una condición y una respuesta. Guarda cada petición.</summary>
public sealed class FakeJira : HttpMessageHandler
{
    private readonly List<(Func<HttpRequestMessage, string, bool> Coincide, Func<HttpRequestMessage, string, HttpResponseMessage> Responder)> _rutas = new();

    public ConcurrentQueue<(HttpMethod Metodo, string Url, string Cuerpo)> Peticiones { get; } = new();

    public FakeJira Get(string ruta, Func<string, string> json, Func<string, bool>? cuando = null) =>
        Agregar(HttpMethod.Get, ruta, (_, url) => Ok(json(url)), cuando);

    public FakeJira Get(string ruta, string json, Func<string, bool>? cuando = null) => Get(ruta, _ => json, cuando);

    public FakeJira Post(string ruta, Func<string, string> jsonSegunCuerpo) =>
        Agregar(HttpMethod.Post, ruta, (r, _) => Ok(jsonSegunCuerpo(r.Content!.ReadAsStringAsync().GetAwaiter().GetResult())), null);

    public FakeJira Estado(HttpMethod metodo, string ruta, HttpStatusCode estado) =>
        Agregar(metodo, ruta, (_, _) => new HttpResponseMessage(estado) { Content = new StringContent("{}") }, null);

    public FakeJira Responder(Func<HttpRequestMessage, string, bool> coincide, Func<HttpRequestMessage, string, HttpResponseMessage> responder)
    {
        _rutas.Add((coincide, responder));
        return this;
    }

    public int Contar(string fragmentoUrl) => Peticiones.Count(p => p.Url.Contains(fragmentoUrl, StringComparison.Ordinal));

    public IJiraCliente Cliente() =>
        new JiraCliente(new HttpClient(this) { BaseAddress = new Uri("https://jira.prueba/") }, NullLogger<JiraCliente>.Instance);

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var url = Uri.UnescapeDataString(request.RequestUri!.PathAndQuery);
        var cuerpo = request.Content is null ? "" : await request.Content.ReadAsStringAsync(ct);
        Peticiones.Enqueue((request.Method, url, cuerpo));
        if (request.Content is not null) request.Content = new StringContent(cuerpo, Encoding.UTF8, "application/json");
        foreach (var (coincide, responder) in _rutas)
            if (coincide(request, url)) return responder(request, url);
        return new HttpResponseMessage(HttpStatusCode.NotFound) { Content = new StringContent($"{{\"errorMessages\":[\"sin ruta simulada: {url}\"]}}") };
    }

    private FakeJira Agregar(HttpMethod metodo, string ruta, Func<HttpRequestMessage, string, HttpResponseMessage> responder, Func<string, bool>? cuando) =>
        Responder((r, url) => r.Method == metodo && url.Split('?')[0] == ruta && (cuando?.Invoke(url) ?? true), responder);

    private static HttpResponseMessage Ok(string json) =>
        new(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
}
