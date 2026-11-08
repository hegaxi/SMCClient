using Microsoft.Extensions.Diagnostics.HealthChecks;
using SMCClient.Api.Procedimientos;

namespace SMCClient.Api;

/// <summary>/salud: la API responde y llega a SQL Server (para el monitoreo de IIS o del balanceador).</summary>
public sealed class SaludSql(ConexionSql conexion) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        try
        {
            await using var cn = await conexion.AbrirAsync(ct);
            return HealthCheckResult.Healthy();
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Sin conexión a SQL Server.", ex);
        }
    }
}
