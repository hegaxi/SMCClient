using SMCClient.Sync.Jira;
using Xunit;

namespace SMCClient.Sync.Tests;

public class JiraFechaYJqlTests
{
    [Theory]
    [InlineData("2026-07-08T09:30:36.291-0600", "2026-07-08T15:30:36.2910000+00:00")]
    [InlineData("2026-08-01T11:00:03.281Z", "2026-08-01T11:00:03.2810000+00:00")]
    [InlineData("2026-07-08T09:30:36-06:00", "2026-07-08T15:30:36.0000000+00:00")]
    public void Convierte_los_formatos_de_fecha_de_Jira(string valor, string esperadoUtc) =>
        Assert.Equal(DateTimeOffset.Parse(esperadoUtc), JiraFecha.Parse(valor));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("no es fecha")]
    public void Devuelve_null_si_no_reconoce_la_fecha(string? valor) => Assert.Null(JiraFecha.Parse(valor));

    [Fact]
    public void JQL_incremental_usa_la_zona_del_usuario_de_Jira_y_excluye_proyectos()
    {
        var zona = TimeZoneInfo.FindSystemTimeZoneById("America/Mexico_City");
        var jql = Jql.Incremental(DateTimeOffset.Parse("2026-11-08T18:05:59Z"), zona, new[] { "TS25", "TSM26" }, "issuetype != Sub-task");

        Assert.Equal("(updated >= \"2026-11-08 12:05\") AND (project not in (\"TS25\", \"TSM26\")) AND (issuetype != Sub-task) ORDER BY updated ASC", jql);
    }

    [Fact]
    public void JQL_de_backfill_de_campo() => Assert.Equal("cf[10099] is not EMPTY", Jql.CampoNoVacio("customfield_10099"));

    [Fact]
    public void Rechaza_ids_de_campo_que_podrian_inyectar_JQL() =>
        Assert.Throws<ArgumentException>(() => Jql.CampoNoVacio("customfield_1) OR (1=1"));

    [Fact]
    public void Escapa_comillas_en_valores() => Assert.Equal("project = \"A\\\"B\"", Jql.Proyecto("A\"B"));
}
