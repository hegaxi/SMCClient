using System.Data;
using Microsoft.Extensions.Options;
using SMCClient.Api.Procedimientos;

namespace SMCClient.Api.Sincronizacion;

public sealed record EstadoFuente(string Fuente, bool DatosVigentes, bool Sincronizando, DateTimeOffset? UltimaSincronizacion);

public interface ICompuertaSincronizacion
{
    /// <summary>Fuentes activas cuyos datos aún no están vigentes (vacío = se puede consultar).</summary>
    Task<IReadOnlyList<EstadoFuente>> FuentesPendientesAsync(CancellationToken ct);
}

/// <summary>
/// "La aplicación sincroniza antes de hacer nada": consulta api.Sync_Estado (con un caché de pocos segundos)
/// y el controlador responde 503 mientras alguna fuente activa no tenga datos vigentes.
/// Para dejar fuera una fuente que ya no se usa, se desactiva en cfg.Fuente.
/// </summary>
public sealed class CompuertaSincronizacion(ConexionSql conexion, IOptions<ApiOptions> opciones) : ICompuertaSincronizacion
{
    private readonly SemaphoreSlim _bloqueo = new(1, 1);
    private IReadOnlyList<EstadoFuente> _pendientes = Array.Empty<EstadoFuente>();
    private DateTimeOffset _leido = DateTimeOffset.MinValue;

    public async Task<IReadOnlyList<EstadoFuente>> FuentesPendientesAsync(CancellationToken ct)
    {
        var vigencia = TimeSpan.FromSeconds(opciones.Value.SegundosCacheEstadoSync);
        if (DateTimeOffset.UtcNow - _leido < vigencia) return _pendientes;

        await _bloqueo.WaitAsync(ct);
        try
        {
            if (DateTimeOffset.UtcNow - _leido < vigencia) return _pendientes;
            await using var cn = await conexion.AbrirAsync(ct);
            await using var cmd = new Microsoft.Data.SqlClient.SqlCommand("api.Sync_Estado", cn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@Detalle", false);
            var pendientes = new List<EstadoFuente>();
            await using (var r = await cmd.ExecuteReaderAsync(ct))
            {
                while (await r.ReadAsync(ct))
                {
                    var estado = new EstadoFuente(r.GetString(0), r.GetBoolean(3), r.GetBoolean(4), r.IsDBNull(1) ? null : r.GetDateTimeOffset(1));
                    if (!estado.DatosVigentes) pendientes.Add(estado);
                }
            }
            _pendientes = pendientes;
            _leido = DateTimeOffset.UtcNow;
            return _pendientes;
        }
        finally
        {
            _bloqueo.Release();
        }
    }
}
