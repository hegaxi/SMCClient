using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace SMCClient.Pruebas;

/// <summary>Solo corre si SMC_TEST_SQL apunta a un SQL Server donde se puedan crear bases (y logins).</summary>
public sealed class FactSiSqlAttribute : FactAttribute
{
    public FactSiSqlAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SMC_TEST_SQL")))
            Skip = "Defina SMC_TEST_SQL con la cadena de conexión a un SQL Server de pruebas (sin Database).";
    }
}

/// <summary>
/// Base de datos desechable: se crea con un nombre único, se despliega con los scripts de db/ en el MISMO orden
/// que deploy.sh (carpetas NN_* y archivos por nombre) y se borra al terminar.
/// </summary>
public class BaseDatosPrueba : IAsyncLifetime
{
    protected readonly string Admin = Environment.GetEnvironmentVariable("SMC_TEST_SQL") ?? "";
    protected readonly string Sufijo = Guid.NewGuid().ToString("N")[..8];

    public string BaseDatos => "SMCClient_Prueba_" + Sufijo;
    public bool Activo => !string.IsNullOrWhiteSpace(Admin);

    /// <summary>Cadena con el usuario administrador hacia la base de prueba.</summary>
    public string Cadena => new SqlConnectionStringBuilder(Admin) { InitialCatalog = BaseDatos }.ConnectionString;

    public virtual async Task InitializeAsync()
    {
        if (!Activo) return;
        await EjecutarAsync("master", $"CREATE DATABASE [{BaseDatos}];");
        // Igual que deploy: si la crea una cuenta de Windows, el dueño pasa a sa (EXECUTE AS OWNER no consulta al dominio).
        await EjecutarAsync("master", $"IF SUSER_SNAME() LIKE N'%\\%' ALTER AUTHORIZATION ON DATABASE::[{BaseDatos}] TO sa;");
        foreach (var script in ScriptsEnOrden()) await EjecutarScriptAsync(script);
    }

    public virtual async Task DisposeAsync()
    {
        if (!Activo) return;
        SqlConnection.ClearAllPools();
        await EjecutarAsync("master", $"ALTER DATABASE [{BaseDatos}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{BaseDatos}];");
    }

    public Task EjecutarAsync(string sql) => EjecutarAsync(BaseDatos, sql);

    public async Task EjecutarAsync(string baseDatos, string sql, params (string Nombre, object Valor)[] parametros)
    {
        await using var cn = new SqlConnection(new SqlConnectionStringBuilder(Admin) { InitialCatalog = baseDatos }.ConnectionString);
        await cn.OpenAsync();
        await using var cmd = new SqlCommand(sql, cn) { CommandTimeout = 120 };
        foreach (var (n, v) in parametros) cmd.Parameters.AddWithValue(n, v);
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<T> EscalarAsync<T>(string sql, params (string Nombre, object Valor)[] parametros)
    {
        await using var cn = new SqlConnection(Cadena);
        await cn.OpenAsync();
        await using var cmd = new SqlCommand(sql, cn);
        foreach (var (n, v) in parametros) cmd.Parameters.AddWithValue(n, v);
        return (T)(await cmd.ExecuteScalarAsync())!;
    }

    /// <summary>Igual que sqlcmd: lotes separados por líneas "GO".</summary>
    public async Task EjecutarScriptAsync(string ruta)
    {
        foreach (var lote in Regex.Split(await File.ReadAllTextAsync(ruta), @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
            if (!string.IsNullOrWhiteSpace(lote)) await EjecutarAsync(BaseDatos, lote);
    }

    public static IEnumerable<string> ScriptsEnOrden() =>
        Directory.GetDirectories(RaizDb())
            .Where(d => Regex.IsMatch(Path.GetFileName(d), @"^\d\d_"))
            .OrderBy(d => Path.GetFileName(d), StringComparer.Ordinal)
            .SelectMany(d => Directory.GetFiles(d, "*.sql").OrderBy(f => Path.GetFileName(f), StringComparer.Ordinal));

    public static string RaizDb()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            if (File.Exists(Path.Combine(dir.FullName, "db", "deploy.sh"))) return Path.Combine(dir.FullName, "db");
        throw new DirectoryNotFoundException("No se encontró la carpeta db/ del repositorio.");
    }
}

/// <summary>Como FactSiSql, para pruebas con varios casos.</summary>
public sealed class TheorySiSqlAttribute : TheoryAttribute
{
    public TheorySiSqlAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SMC_TEST_SQL")))
            Skip = "Defina SMC_TEST_SQL con la cadena de conexión a un SQL Server de pruebas (sin Database).";
    }
}
