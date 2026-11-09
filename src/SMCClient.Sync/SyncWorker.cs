using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SMCClient.Sync.Configuracion;

namespace SMCClient.Sync;

/// <summary>
/// Servicio en segundo plano. El primer ciclo corre al arrancar: como ninguna entidad tiene una ejecución
/// correcta, todo está vencido y se hace la sincronización completa antes de que los datos se consideren vigentes.
/// Después revisa cada IntervaloRevisionSegundos qué entidades vencieron y atiende las solicitudes.
/// </summary>
public sealed class SyncWorker(Sincronizador sincronizador, IOptions<SmcSyncOptions> opciones, ILogger<SyncWorker> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        log.LogInformation("Worker de sincronización iniciado como {Propietario} para {Fuentes}.",
            sincronizador.Propietario, string.Join(", ", opciones.Value.Fuentes.Select(f => f.Codigo)));
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(Math.Max(5, opciones.Value.IntervaloRevisionSegundos)));
        try
        {
            do
            {
                try
                {
                    await sincronizador.EjecutarCicloAsync(ct);
                }
                catch (Exception ex) when (!ct.IsCancellationRequested)
                {
                    log.LogError(ex, "Error no controlado en el ciclo de sincronización; se reintenta en el siguiente.");
                }
            } while (await timer.WaitForNextTickAsync(ct));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            log.LogInformation("Worker de sincronización detenido.");
        }
    }
}
