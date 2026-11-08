using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SMCClient.Sync.Configuracion;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Extractores;
using SMCClient.Sync.Jira;
using Xunit;

namespace SMCClient.Sync.Tests;

/// <summary>Solo corre si la variable SMC_TEST_SQL apunta a una base SMCClient desplegada.</summary>
public sealed class FactSiSqlAttribute : FactAttribute
{
    public FactSiSqlAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SMC_TEST_SQL")))
            Skip = "Defina SMC_TEST_SQL con la cadena de conexión a una base SMCClient desplegada.";
    }
}

/// <summary>
/// Worker completo (Sincronizador + SyncRepositorio reales) contra SQL Server y un Jira simulado con la forma
/// de las respuestas de Jira Cloud. Cada prueba usa una fuente nueva para no chocar con otros datos.
/// </summary>
public class SincronizadorIntegracionTests
{
    private static readonly string Cadena = Environment.GetEnvironmentVariable("SMC_TEST_SQL") ?? "";

    [FactSiSql]
    public async Task Sincroniza_todo_al_arrancar_luego_solo_lo_vencido_y_atiende_solicitudes()
    {
        var fuente = "it" + Guid.NewGuid().ToString("N")[..8];
        await Ejecutar("EXEC sync.Fuente_Registrar @Codigo = @f, @UrlBase = N'https://jira.prueba'; EXEC sync.Proyecto_Excluir @Fuente = @f, @Clave = 'TST';", fuente);
        var jira = JiraSimulado();
        var sincronizador = Crear(fuente, jira);

        // 1. Primera corrida: nada tiene ejecución correcta, así que se sincroniza todo.
        Assert.True(await sincronizador.SincronizarFuenteAsync(fuente, forzar: false, CancellationToken.None));

        Assert.Equal(3, await Escalar<int>("SELECT COUNT(*) FROM ops.Issue i JOIN cfg.Fuente f ON f.FuenteId = i.FuenteId WHERE f.Codigo = @f", fuente));
        Assert.Equal(0, await Escalar<int>("SELECT COUNT(*) FROM ops.Issue i JOIN cfg.Fuente f ON f.FuenteId = i.FuenteId WHERE f.Codigo = @f AND i.Clave LIKE 'TST-%'", fuente));
        Assert.Equal(2, await Escalar<int>("SELECT COUNT(*) FROM ops.Worklog w JOIN cfg.Fuente f ON f.FuenteId = w.FuenteId WHERE f.Codigo = @f AND w.Eliminado = 0", fuente));
        Assert.Equal(1, await Escalar<int>("SELECT COUNT(*) FROM ops.Worklog w JOIN cfg.Fuente f ON f.FuenteId = w.FuenteId WHERE f.Codigo = @f AND w.Eliminado = 1", fuente));
        Assert.Equal(2, await Escalar<int>("SELECT COUNT(*) FROM ops.IssueSla s JOIN ops.Issue i ON i.IssueSk = s.IssueSk JOIN cfg.Fuente f ON f.FuenteId = i.FuenteId WHERE f.Codigo = @f", fuente));
        Assert.Equal(1, await Escalar<int>("SELECT COUNT(*) FROM ops.IssueCambio c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId WHERE f.Codigo = @f", fuente));
        Assert.Equal(5m, await Escalar<decimal>("SELECT StoryPoints FROM ops.Issue i JOIN cfg.Fuente f ON f.FuenteId = i.FuenteId WHERE f.Codigo = @f AND i.Clave = 'SCR-7'", fuente));
        Assert.True(await DatosVigentes(fuente));
        Assert.Contains(jira.Peticiones, p => p.Url.StartsWith("/rest/api/3/search/jql") && p.Url.Contains("project not in (\"TST\")"));
        Assert.Equal(0, jira.Contar("/rest/servicedeskapi/request/5002/"));   // SCR-7 es Scrum: no se piden SLA
        Assert.Equal(1, await Escalar<int>("SELECT COUNT(*) FROM sync.Candado c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId WHERE f.Codigo = @f AND c.Propietario IS NULL", fuente));

        // 2. Segunda corrida inmediata: nada venció, no se vuelve a pedir issues; sí corre la conciliación diaria.
        var busquedas = jira.Peticiones.Count(p => p.Url.StartsWith("/rest/api/3/search/jql") && !p.Url.Contains("fields=id"));
        await sincronizador.SincronizarFuenteAsync(fuente, forzar: false, CancellationToken.None);
        Assert.Equal(busquedas, jira.Peticiones.Count(p => p.Url.StartsWith("/rest/api/3/search/jql") && !p.Url.Contains("fields=id")));
        Assert.Equal(1, await Escalar<int>("SELECT COUNT(*) FROM ops.Issue i JOIN cfg.Fuente f ON f.FuenteId = i.FuenteId WHERE f.Codigo = @f AND i.Eliminado = 1 AND i.Clave = 'MDA-2'", fuente));

        // 3. "Sincronizar ahora" desde la interfaz: se fuerza una corrida desde la marca de agua.
        await Ejecutar("EXEC api.Sync_Solicitar @Fuente = @f, @SolicitadoPor = N'prueba';", fuente);
        await sincronizador.AtenderSolicitudesAsync(CancellationToken.None);
        Assert.Equal(busquedas + 1, jira.Peticiones.Count(p => p.Url.StartsWith("/rest/api/3/search/jql") && !p.Url.Contains("fields=id")));
        Assert.Contains(jira.Peticiones, p => p.Url.Contains("updated >= \"2026-11-02 11:55\""));   // marca 12:00 -06:00 menos 5 min
        Assert.Equal("hecha", await Escalar<string>("SELECT TOP (1) s.Estado FROM sync.Solicitud s JOIN cfg.Fuente f ON f.FuenteId = s.FuenteId WHERE f.Codigo = @f ORDER BY s.SolicitudId DESC", fuente));
    }

    [FactSiSql]
    public async Task Si_otra_instancia_tiene_el_candado_no_sincroniza()
    {
        var fuente = "it" + Guid.NewGuid().ToString("N")[..8];
        await Ejecutar("""
            EXEC sync.Fuente_Registrar @Codigo = @f, @UrlBase = N'https://jira.prueba';
            DECLARE @e bigint; EXEC sync.Ejecucion_Iniciar @Fuente = @f, @Entidad = 'campo', @Modo = 'catalogo', @Propietario = N'otra-instancia', @EjecucionId = @e OUTPUT;
            """, fuente);
        var jira = JiraSimulado();

        Assert.False(await Crear(fuente, jira).SincronizarFuenteAsync(fuente, forzar: false, CancellationToken.None));
        Assert.Empty(jira.Peticiones);
    }

    [FactSiSql]
    public async Task Al_detener_el_servicio_cierra_la_ejecucion_y_libera_el_candado()
    {
        var fuente = "it" + Guid.NewGuid().ToString("N")[..8];
        await Ejecutar("EXEC sync.Fuente_Registrar @Codigo = @f, @UrlBase = N'https://jira.prueba';", fuente);
        using var cts = new CancellationTokenSource();
        var jira = new FakeJira().Responder((_, url) => url.StartsWith("/rest/api/3/field"), (_, _) =>
        {
            cts.Cancel();   // se detiene el servicio mientras Jira está respondiendo
            throw new OperationCanceledException(cts.Token);
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Crear(fuente, jira).SincronizarFuenteAsync(fuente, forzar: false, cts.Token));

        Assert.Equal("error", await Escalar<string>("SELECT TOP (1) e.Estado FROM sync.Ejecucion e JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId WHERE f.Codigo = @f ORDER BY e.EjecucionId DESC", fuente));
        Assert.Equal(1, await Escalar<int>("SELECT COUNT(*) FROM sync.Candado c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId WHERE f.Codigo = @f AND c.Propietario IS NULL", fuente));
    }

    [FactSiSql]
    public async Task Tras_un_error_espera_antes_de_reintentar_y_los_datos_no_quedan_vigentes()
    {
        var fuente = "it" + Guid.NewGuid().ToString("N")[..8];
        await Ejecutar("EXEC sync.Fuente_Registrar @Codigo = @f, @UrlBase = N'https://jira.prueba';", fuente);
        var jira = new FakeJira().Estado(HttpMethod.Get, "/rest/api/3/field", System.Net.HttpStatusCode.InternalServerError);
        var sincronizador = Crear(fuente, jira);

        await sincronizador.SincronizarFuenteAsync(fuente, forzar: false, CancellationToken.None);
        var llamadas = jira.Contar("/rest/api/3/field");
        await sincronizador.SincronizarFuenteAsync(fuente, forzar: false, CancellationToken.None);

        Assert.Equal(1, llamadas);
        Assert.Equal(1, jira.Contar("/rest/api/3/field"));     // no reintentó en el siguiente ciclo
        Assert.False(await DatosVigentes(fuente));            // el controlador seguiría respondiendo 503
        Assert.Contains("500", await Escalar<string>("SELECT TOP (1) e.Mensaje FROM sync.Ejecucion e JOIN cfg.Fuente f ON f.FuenteId = e.FuenteId WHERE f.Codigo = @f AND e.Entidad = 'campo' ORDER BY e.EjecucionId DESC", fuente));
    }

    private static Sincronizador Crear(string fuente, FakeJira jira)
    {
        var opciones = Options.Create(new SmcSyncOptions
        {
            Propietario = "prueba-integracion",
            Fuentes = { new FuenteJiraOptions { Codigo = fuente, UrlBase = "https://jira.prueba", Token = "x" } },
        });
        IExtractor[] extractores =
        {
            new CampoExtractor(), new EstadoExtractor(), new ProyectoExtractor(), new IssueExtractor(), new ChangelogExtractor(),
            new WorklogExtractor(), new WorklogEliminadoExtractor(), new SlaExtractor(),
        };
        return new Sincronizador(new SyncRepositorio(Cadena, 120), new FabricaFija(jira), extractores, opciones, TimeProvider.System,
                                 NullLogger<Sincronizador>.Instance);
    }

    private sealed class FabricaFija(FakeJira jira) : IJiraClienteFactory
    {
        public IJiraCliente Crear(string codigoFuente) => jira.Cliente();
    }

    private static FakeJira JiraSimulado() => new FakeJira()
        .Get("/rest/api/3/myself", """{"timeZone":"America/Mexico_City"}""")
        .Get("/rest/api/3/field", """
            [{"id":"summary","name":"Summary","custom":false,"schema":{"type":"string","system":"summary"}},
             {"id":"status","name":"Status","custom":false,"schema":{"type":"status","system":"status"}},
             {"id":"project","name":"Project","custom":false,"schema":{"type":"project","system":"project"}},
             {"id":"updated","name":"Updated","custom":false,"schema":{"type":"datetime","system":"updated"}},
             {"id":"customfield_10016","name":"Story point estimate","custom":true,"schema":{"type":"number","custom":"com.pyxis.greenhopper.jira:jsw-story-points","customId":10016}},
             {"id":"customfield_10055","name":"Time to resolution","custom":true,"schema":{"type":"sd-servicelevelagreement","custom":"com.atlassian.servicedesk:sd-sla-field","customId":10055}}]
            """)
        .Get("/rest/api/3/status", """[{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},{"id":"10001","name":"Done","statusCategory":{"key":"done"}}]""")
        .Get("/rest/api/3/project/search", """
            {"values":[{"id":"900","key":"MDA","name":"Mesa","projectTypeKey":"service_desk"},
                       {"id":"901","key":"SCR","name":"Scrum","projectTypeKey":"software"},
                       {"id":"902","key":"TST","name":"Pruebas","projectTypeKey":"software"}],"isLast":true}
            """)
        // Conciliación: MDA-2 ya no existe en Jira.
        .Get("/rest/api/3/search/jql", url => url.Contains("project = \"MDA\"") ? """{"issues":[{"id":"5001"}],"isLast":true}"""
                                                                                  : """{"issues":[{"id":"5002"}],"isLast":true}""",
             url => url.Contains("fields=id"))
        .Get("/rest/api/3/search/jql", """
            {"issues":[
              {"id":"5001","key":"MDA-1","fields":{"summary":"Falla","project":{"id":"900","key":"MDA","projectTypeKey":"service_desk"},
                "status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},"updated":"2026-11-02T10:00:00.000-0600"}},
              {"id":"5005","key":"MDA-2","fields":{"summary":"Otra","project":{"id":"900","key":"MDA","projectTypeKey":"service_desk"},
                "status":{"id":"3","name":"In Progress","statusCategory":{"key":"indeterminate"}},"updated":"2026-11-02T11:00:00.000-0600"}},
              {"id":"5002","key":"SCR-7","fields":{"summary":"Historia","project":{"id":"901","key":"SCR","projectTypeKey":"software"},
                "status":{"id":"10001","name":"Done","statusCategory":{"key":"done"}},"updated":"2026-11-02T12:00:00.000-0600","customfield_10016":5}},
              {"id":"5009","key":"TST-1","fields":{"summary":"Pruebas","project":{"id":"902","key":"TST","projectTypeKey":"software"},
                "updated":"2026-11-02T09:00:00.000-0600"}}],
             "isLast":true}
            """)
        .Post("/rest/api/3/changelog/bulkfetch", _ => """
            {"issueChangeLogs":[{"issueId":"5001","changeHistories":[{"id":"h1","author":{"accountId":"a1"},"created":"2026-11-02T09:30:00.000-0600",
              "items":[{"field":"status","fieldId":"status","from":"1","fromString":"To Do","to":"3","toString":"In Progress"}]}]}]}
            """)
        .Get("/rest/api/3/worklog/updated", """{"values":[{"worklogId":71,"updatedTime":1},{"worklogId":72,"updatedTime":2},{"worklogId":73,"updatedTime":3}],"until":1793600000000,"lastPage":true}""")
        .Post("/rest/api/3/worklog/list", _ => """
            [{"id":"71","issueId":"5001","author":{"accountId":"a1","displayName":"Agente","accountType":"atlassian"},"started":"2026-11-02T09:00:00.000-0600","timeSpentSeconds":3600,"updated":"2026-11-02T10:00:00.000-0600"},
             {"id":"72","issueId":"5002","author":{"accountId":"a2","displayName":"Dev","accountType":"atlassian"},"started":"2026-11-02T09:00:00.000-0600","timeSpentSeconds":7200,"updated":"2026-11-02T10:00:00.000-0600"},
             {"id":"73","issueId":"5002","author":{"accountId":"a2","displayName":"Dev","accountType":"atlassian"},"started":"2026-11-02T09:00:00.000-0600","timeSpentSeconds":600,"updated":"2026-11-02T10:00:00.000-0600"}]
            """)
        .Get("/rest/api/3/worklog/deleted", """{"values":[{"worklogId":73,"updatedTime":1793600000000}],"until":1793600000000,"lastPage":true}""")
        .Get("/rest/servicedeskapi/request/5001/sla", """
            {"values":[{"id":"86","name":"Time to resolution","ongoingCycle":{"startTime":{"epochMillis":1793600000000},"breachTime":{"epochMillis":1793700000000},
              "breached":false,"paused":false,"withinCalendarHours":true,"goalDuration":{"millis":28800000},"elapsedTime":{"millis":3600000},"remainingTime":{"millis":25200000}}},
              {"id":"87","name":"Time to first response","completedCycles":[{"startTime":{"epochMillis":1793600000000},"stopTime":{"epochMillis":1793601000000},"breached":false,
              "goalDuration":{"millis":14400000},"elapsedTime":{"millis":1000000},"remainingTime":{"millis":13400000}}]}],"isLastPage":true}
            """)
        .Get("/rest/servicedeskapi/request/5005/sla", """{"values":[],"isLastPage":true}""");

    private static async Task<bool> DatosVigentes(string fuente)
    {
        await using var cn = new SqlConnection(Cadena);
        await cn.OpenAsync();
        await using var cmd = new SqlCommand("api.Sync_Estado", cn) { CommandType = System.Data.CommandType.StoredProcedure };
        cmd.Parameters.AddWithValue("@Detalle", false);
        await using var r = await cmd.ExecuteReaderAsync();
        while (await r.ReadAsync())
            if (r.GetString(0) == fuente) return r.GetBoolean(3);
        return false;
    }

    private static async Task Ejecutar(string sql, string fuente)
    {
        await using var cn = new SqlConnection(Cadena);
        await cn.OpenAsync();
        await using var cmd = new SqlCommand(sql, cn);
        cmd.Parameters.AddWithValue("@f", fuente);
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task<T> Escalar<T>(string sql, string fuente)
    {
        await using var cn = new SqlConnection(Cadena);
        await cn.OpenAsync();
        await using var cmd = new SqlCommand(sql, cn);
        cmd.Parameters.AddWithValue("@f", fuente);
        return (T)(await cmd.ExecuteScalarAsync())!;
    }
}
