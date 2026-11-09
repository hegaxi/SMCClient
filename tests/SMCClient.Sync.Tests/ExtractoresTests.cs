using System.Text.Json;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Extractores;
using Xunit;

namespace SMCClient.Sync.Tests;

public class ExtractoresTests
{
    private static readonly ConfiguracionFuente Fuente = new(1, "prueba", "https://jira.prueba", null,
        Array.Empty<EntidadConfig>(), new[] { "TST" }, Array.Empty<ProyectoVigente>());

    private static ContextoExtraccion Contexto(FakeJira jira, string entidad, string endpoint, int lote = 100, string? parametros = null,
                                               string modo = "incremental", IssuesCambiados? issues = null, string? solicitud = null) => new()
    {
        Fuente = Fuente,
        Entidad = new EntidadConfig(entidad, 1, "incremental", 15, endpoint, lote, parametros, null),
        Jira = jira.Cliente(),
        Modo = modo,
        Desde = DateTimeOffset.Parse("2026-11-01T00:00:00Z"),
        Issues = issues ?? new IssuesCambiados(),
        ParametrosSolicitud = solicitud is null ? null : JsonDocument.Parse(solicitud).RootElement.Clone(),
    };

    private static async Task<List<DocumentoJira>> Todo(IExtractor e, ContextoExtraccion ctx)
    {
        var r = new List<DocumentoJira>();
        await foreach (var p in e.ExtraerAsync(ctx, CancellationToken.None)) r.AddRange(p);
        return r;
    }

    [Fact]
    public async Task Issues_pagina_con_nextPageToken_y_registra_los_issues_cambiados()
    {
        var jira = new FakeJira()
            .Get("/rest/api/3/myself", """{"timeZone":"America/Mexico_City"}""")
            .Get("/rest/api/3/search/jql", """{"issues":[{"id":"1","key":"A-1","fields":{"updated":"2026-11-02T10:00:00.000-0600","project":{"projectTypeKey":"service_desk"}}}],"nextPageToken":"p2"}""",
                 url => !url.Contains("nextPageToken"))
            .Get("/rest/api/3/search/jql", """{"issues":[{"id":"2","key":"B-1","fields":{"updated":"2026-11-03T10:00:00.000-0600","project":{"projectTypeKey":"software"}}}],"isLast":true}""",
                 url => url.Contains("nextPageToken=p2"));
        var ctx = Contexto(jira, "issue", "/rest/api/3/search/jql", parametros: """{"fields":"*all","jqlBase":""}""");

        var docs = await Todo(new IssueExtractor(), ctx);

        Assert.Equal(new[] { "1", "2" }, docs.Select(d => d.IdExterno));
        Assert.Equal(DateTimeOffset.Parse("2026-11-02T16:00:00Z"), docs[0].Actualizado);
        Assert.Equal(2, ctx.Issues.Cantidad);
        Assert.Equal("service_desk", ctx.Issues.Todos.Single(i => i.IssueId == "1").TipoProyecto);
        var url = jira.Peticiones.First(p => p.Url.StartsWith("/rest/api/3/search/jql")).Url;
        Assert.Contains("updated >= \"2026-10-31 18:00\"", url);      // 2026-11-01T00:00Z en America/Mexico_City
        Assert.Contains("project not in (\"TST\")", url);
        Assert.Contains("fields=*all", url);
    }

    [Fact]
    public async Task Backfill_de_campo_usa_cf_is_not_EMPTY()
    {
        var jira = new FakeJira().Get("/rest/api/3/search/jql", """{"issues":[],"isLast":true}""");
        var ctx = Contexto(jira, "issue", "/rest/api/3/search/jql", modo: "backfill", solicitud: """{"campoId":"customfield_10099"}""");

        await Todo(new IssueExtractor(), ctx);

        Assert.Contains("(cf[10099] is not EMPTY) AND (project not in (\"TST\"))", jira.Peticiones.Single().Url);
    }

    [Fact]
    public async Task Changelog_junta_las_paginas_en_un_documento_por_issue()
    {
        var jira = new FakeJira().Post("/rest/api/3/changelog/bulkfetch", cuerpo => cuerpo.Contains("\"nextPageToken\":\"t2\"")
            ? """{"issueChangeLogs":[{"issueId":"1","changeHistories":[{"id":"h2"}]}]}"""
            : """{"issueChangeLogs":[{"issueId":"1","changeHistories":[{"id":"h1"}]},{"issueId":"2","changeHistories":[{"id":"h9"}]}],"nextPageToken":"t2"}""");
        var issues = new IssuesCambiados();
        issues.Agregar(new IssueCambiado("1", "A-1", null));
        issues.Agregar(new IssueCambiado("2", "A-2", null));

        var docs = await Todo(new ChangelogExtractor(), Contexto(jira, "changelog", "/rest/api/3/changelog/bulkfetch", issues: issues));

        Assert.Equal("""{"issueId":"1","histories":[{"id":"h1"},{"id":"h2"}]}""", docs.Single(d => d.IdExterno == "1").Json);
        Assert.Equal(2, jira.Peticiones.Count);
        Assert.DoesNotContain("nextPageToken", jira.Peticiones.First().Cuerpo);   // null no se envía
    }

    [Fact]
    public async Task Worklogs_pide_ids_actualizados_y_despues_la_lista()
    {
        var jira = new FakeJira()
            .Get("/rest/api/3/worklog/updated", """{"values":[{"worklogId":10,"updatedTime":1},{"worklogId":11,"updatedTime":2}],"until":1793500000000,"lastPage":false}""",
                 url => url.Contains("since=1793491200000"))
            .Get("/rest/api/3/worklog/updated", """{"values":[{"worklogId":12,"updatedTime":3}],"until":1793500000001,"lastPage":true}""",
                 url => url.Contains("since=1793500000000"))
            .Post("/rest/api/3/worklog/list", cuerpo =>
            {
                Assert.Contains("[10,11,12]", cuerpo);
                return """[{"id":"10","issueId":"1","updated":"2026-11-02T10:00:00.000-0600"},{"id":"11","issueId":"1"},{"id":"12","issueId":"2"}]""";
            });

        var docs = await Todo(new WorklogExtractor(), Contexto(jira, "worklog", "/rest/api/3/worklog/updated", parametros: """{"lista":"/rest/api/3/worklog/list"}"""));

        Assert.Equal(new[] { "10", "11", "12" }, docs.Select(d => d.IdExterno));
    }

    [Fact]
    public async Task SLA_solo_para_mesa_de_ayuda_y_omite_los_que_no_son_de_JSM()
    {
        var jira = new FakeJira()
            .Get("/rest/servicedeskapi/request/1/sla", """{"values":[{"id":"86","name":"Time to resolution"}],"isLastPage":true}""")
            .Estado(HttpMethod.Get, "/rest/servicedeskapi/request/3/sla", System.Net.HttpStatusCode.NotFound);
        var issues = new IssuesCambiados();
        issues.Agregar(new IssueCambiado("1", "MDA-1", "service_desk"));
        issues.Agregar(new IssueCambiado("2", "SCR-1", "software"));
        issues.Agregar(new IssueCambiado("3", "MDA-2", "service_desk"));

        var docs = await Todo(new SlaExtractor(), Contexto(jira, "sla", "/rest/servicedeskapi/request/{issueIdOrKey}/sla",
            parametros: """{"soloTipoProyecto":"service_desk"}""", issues: issues));

        Assert.Equal("1", docs.Single().IdExterno);
        Assert.Equal("""{"values":[{"id":"86","name":"Time to resolution"}]}""", docs.Single().Json);
        Assert.Equal(0, jira.Contar("/request/2/"));
    }

    [Fact]
    public async Task Comentarios_junta_todas_las_paginas_por_issue_y_omite_los_borrados()
    {
        var jira = new FakeJira()
            .Get("/rest/api/2/issue/1/comment", url => url.Contains("startAt=0")
                ? """{"startAt":0,"maxResults":1,"total":2,"comments":[{"id":"c1","body":"uno","jsdPublic":true}]}"""
                : """{"startAt":1,"maxResults":1,"total":2,"comments":[{"id":"c2","body":"dos","jsdPublic":false}]}""")
            .Estado(HttpMethod.Get, "/rest/api/2/issue/2/comment", System.Net.HttpStatusCode.NotFound);
        var issues = new IssuesCambiados();
        issues.Agregar(new IssueCambiado("1", "MDA-1", "service_desk"));
        issues.Agregar(new IssueCambiado("2", "MDA-2", "service_desk"));

        var docs = await Todo(new ComentarioExtractor(), Contexto(jira, "comentario", "/rest/api/2/issue/{issueIdOrKey}/comment", issues: issues));

        var doc = Assert.Single(docs);
        Assert.Equal("1", doc.IdExterno);
        Assert.Equal("""{"issueId":"1","comments":[{"id":"c1","body":"uno","jsdPublic":true},{"id":"c2","body":"dos","jsdPublic":false}]}""", doc.Json);
        Assert.Equal(2, jira.Contar("/rest/api/2/issue/1/comment"));
    }
}
