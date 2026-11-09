using Microsoft.Data.SqlClient;

namespace SMCClient.Api.Procedimientos;

/// <summary>Cadena de conexión de la API (usuario con rol smc_api: solo EXECUTE sobre el esquema api).</summary>
public sealed class ConexionSql(string cadena)
{
    public async Task<SqlConnection> AbrirAsync(CancellationToken ct)
    {
        var cn = new SqlConnection(cadena);
        await cn.OpenAsync(ct);
        return cn;
    }
}
