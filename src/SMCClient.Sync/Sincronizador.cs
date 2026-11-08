using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SMCClient.Sync.Configuracion;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Extractores;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync;

/// <summary>
/// Orquesta la sincronización: por cada fuente recorre las entidades en el orden de cfg.EntidadSync,
/// trae de Jira solo lo que venció (o todo si se fuerza), lo carga a raw.Documento y pide a la base que lo integre.
/// Toda la lógica de interpretación vive en SQL; aquí solo se habla con Jira y se mueve JSON.
/// </summary>
public sealed class Sincronizador
{
    private readonly ISyncRepositorio _repo;
    private readonly IJiraClienteFactory _jira;
    private readonly Dictionary<string, IExtractor> _extractores;
    private readonly SmcSyncOptions _op;
    private readonly TimeProvider _tiempo;
    private readonly ILogger<Sincronizador> _log;

    public Sincronizador(ISyncRepositorio repo, IJiraClienteFactory jira, IEnumerable<IExtractor> extractores,
                         IOptions<SmcSyncOptions> opciones, TimeProvider tiempo, ILogger<Sincronizador> log)
    {
        _repo = repo;
        _jira = jira;
        _extractores = extractores.ToDictionary(e => e.Entidad, StringComparer.OrdinalIgnoreCase);
        _op = opciones.Value;
        _tiempo = tiempo;
        _log = log;
    }

    public string Propietario => _op.Propietario ?? $"{Environment.MachineName}:{Environment.ProcessId}";

    /// <summary>Un ciclo del worker: entidades vencidas de cada fuente y después las solicitudes pendientes.</summary>
    public async Task EjecutarCicloAsync(CancellationToken ct)
    {
        foreach (var fuente in _op.Fuentes)
        {
            try
            {
                await SincronizarFuenteAsync(fuente.Codigo, forzar: false, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
            {
                _log.LogError(ex, "Falló la sincronización de la fuente {Fuente}.", fuente.Codigo);
            }
        }
        await AtenderSolicitudesAsync(ct);
    }

    /// <summary>Sincroniza una fuente. Devuelve false si otra instancia tenía el candado.</summary>
    public async Task<bool> SincronizarFuenteAsync(string fuente, bool forzar, CancellationToken ct)
    {
        var cfg = await _repo.ObtenerConfiguracionAsync(fuente, ct);
        var jira = _jira.Crear(fuente);
        var issues = new IssuesCambiados();
        var issueOk = false;
        try
        {
            foreach (var e in cfg.Entidades)
            {
                if (e.Modo == "dependiente")
                {
                    // changelog y SLA se piden solo para los issues que cambiaron en esta corrida.
                    if (!issueOk || issues.Cantidad == 0) continue;
                }
                else if (!forzar && !Vencida(e))
                {
                    continue;
                }

                var ok = await EjecutarEntidadAsync(cfg, e, jira, modoForzado: null, parametros: null, issues, ct);
                if (e.Entidad == "issue") issueOk = ok;
            }

            if (ConciliacionVencida(cfg)) await ConciliarAsync(cfg, jira, ct);
            return true;
        }
        catch (CandadoOcupadoException)
        {
            _log.LogInformation("La fuente {Fuente} la está sincronizando otra instancia; se omite en este ciclo.", fuente);
            return false;
        }
        finally
        {
            await _repo.LiberarCandadoAsync(fuente, Propietario, CancellationToken.None);
        }
    }

    /// <summary>Atiende la cola sync.Solicitud: botón "Sincronizar ahora", backfill y conciliación.</summary>
    public async Task AtenderSolicitudesAsync(CancellationToken ct)
    {
        for (var i = 0; i < _op.MaxSolicitudesPorCiclo; i++)
        {
            // Solo se toman solicitudes de las fuentes que atiende esta instancia (o sin fuente).
            var sol = await _repo.TomarSolicitudAsync(Propietario, _op.Fuentes.Select(f => f.Codigo).ToList(), ct);
            if (sol is null) return;

            try
            {
                var ok = sol.Modo switch
                {
                    "incremental" or "inicial" => await SolicitudIncrementalAsync(sol, ct),
                    "backfill" => await BackfillAsync(sol, ct),
                    "conciliacion" => await ConciliacionSolicitadaAsync(sol, ct),
                    _ => throw new InvalidOperationException($"Modo de solicitud desconocido: {sol.Modo}"),
                };
                await _repo.TerminarSolicitudAsync(sol.SolicitudId, ok ? "hecha" : "pendiente", CancellationToken.None);
                if (!ok) return;   // candado ocupado: se reintenta en el siguiente ciclo
            }
            catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
            {
                _log.LogError(ex, "Falló la solicitud {Solicitud} ({Modo}).", sol.SolicitudId, sol.Modo);
                await _repo.TerminarSolicitudAsync(sol.SolicitudId, "error", CancellationToken.None);
            }
        }
    }

    private async Task<bool> SolicitudIncrementalAsync(SolicitudSync sol, CancellationToken ct)
    {
        var ok = true;
        foreach (var f in sol.Fuente is null ? _op.Fuentes.Select(x => x.Codigo) : new[] { sol.Fuente })
            ok &= await SincronizarFuenteAsync(f, forzar: true, ct);
        return ok;
    }

    private async Task<bool> BackfillAsync(SolicitudSync sol, CancellationToken ct)
    {
        var fuente = sol.Fuente ?? throw new InvalidOperationException("Backfill sin fuente.");
        var cfg = await _repo.ObtenerConfiguracionAsync(fuente, ct);
        var jira = _jira.Crear(fuente);
        var issues = new IssuesCambiados();
        using var parametros = JsonDocument.Parse(sol.Parametros ?? "{}");
        var esProyecto = parametros.RootElement.TryGetProperty("proyecto", out _);
        try
        {
            var eIssue = cfg.Entidades.FirstOrDefault(e => e.Entidad == "issue") ?? throw new InvalidOperationException("La entidad issue no está activa.");
            if (!await EjecutarEntidadAsync(cfg, eIssue, jira, "backfill", parametros.RootElement, issues, ct)) return true;

            // Un proyecto que vuelve a incluirse necesita también su historial, worklogs y SLA.
            if (esProyecto && issues.Cantidad > 0)
                foreach (var e in cfg.Entidades.Where(e => e.Entidad is "changelog" or "worklog" or "sla"))
                    await EjecutarEntidadAsync(cfg, e, jira, "backfill", parametros.RootElement, issues, ct);
            return true;
        }
        catch (CandadoOcupadoException)
        {
            return false;
        }
        finally
        {
            await _repo.LiberarCandadoAsync(fuente, Propietario, CancellationToken.None);
        }
    }

    private async Task<bool> ConciliacionSolicitadaAsync(SolicitudSync sol, CancellationToken ct)
    {
        foreach (var f in sol.Fuente is null ? _op.Fuentes.Select(x => x.Codigo) : new[] { sol.Fuente })
        {
            var cfg = await _repo.ObtenerConfiguracionAsync(f, ct);
            try
            {
                await ConciliarAsync(cfg, _jira.Crear(f), ct);
            }
            catch (CandadoOcupadoException)
            {
                return false;
            }
            finally
            {
                await _repo.LiberarCandadoAsync(f, Propietario, CancellationToken.None);
            }
        }
        return true;
    }

    /// <summary>Ejecuta una entidad completa. Devuelve false si falló (ya quedó registrado en sync.Ejecucion).</summary>
    private async Task<bool> EjecutarEntidadAsync(ConfiguracionFuente cfg, EntidadConfig e, IJiraCliente jira, string? modoForzado,
                                                  JsonElement? parametros, IssuesCambiados issues, CancellationToken ct)
    {
        if (!_extractores.TryGetValue(e.Entidad, out var extractor))
        {
            _log.LogWarning("No hay extractor para la entidad {Entidad}; revise cfg.EntidadSync.", e.Entidad);
            return false;
        }

        var desde = _tiempo.GetUtcNow();
        string modo;
        if (modoForzado is not null) modo = modoForzado;
        else if (e.Modo == "catalogo") modo = "catalogo";
        else
        {
            var marca = await _repo.ObtenerMarcaAguaAsync(cfg.Codigo, e.Entidad, ct);
            desde = marca.Desde;
            modo = e.Modo == "dependiente" || !marca.EsCargaInicial ? "incremental" : "inicial";
        }

        var ejecucionId = await _repo.IniciarEjecucionAsync(cfg.Codigo, e.Entidad, modo, Propietario, _op.DuracionCandadoSegundos, ct);
        var reloj = Stopwatch.StartNew();
        var leidos = 0;
        try
        {
            var ctx = new ContextoExtraccion
            {
                Fuente = cfg, Entidad = e, Jira = jira, Modo = modo, Desde = desde, ParametrosSolicitud = parametros, Issues = issues,
                MaxConcurrencia = _op.Fuentes.FirstOrDefault(f => string.Equals(f.Codigo, cfg.Codigo, StringComparison.OrdinalIgnoreCase))?.MaxConcurrencia ?? 4,
            };

            await foreach (var pagina in extractor.ExtraerAsync(ctx, ct))
            {
                foreach (var bloque in pagina.Chunk(Math.Max(1, _op.DocumentosPorCarga)))
                    await _repo.CargarDocumentosAsync(ejecucionId, bloque, ct);
                leidos += pagina.Count;

                // Renueva el candado durante cargas largas (p. ej. la carga inicial de issues).
                if (reloj.Elapsed > TimeSpan.FromSeconds(_op.DuracionCandadoSegundos / 3.0))
                {
                    if (!await _repo.RenovarCandadoAsync(cfg.Codigo, Propietario, _op.DuracionCandadoSegundos, ct))
                        throw new CandadoPerdidoException(cfg.Codigo);
                    reloj.Restart();
                }
            }

            var procesados = await _repo.ProcesarPendientesAsync(cfg.FuenteId, ejecucionId, e.Entidad, ct);
            await _repo.FinalizarEjecucionAsync(ejecucionId, "ok", $"{leidos} documentos leídos, {procesados} integrados.", CancellationToken.None);
            _log.LogInformation("{Fuente}/{Entidad} ({Modo}): {Leidos} leídos, {Procesados} integrados.", cfg.Codigo, e.Entidad, modo, leidos, procesados);
            return true;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            await _repo.FinalizarEjecucionAsync(ejecucionId, "error", "Cancelado al detener el servicio.", CancellationToken.None);
            throw;
        }
        catch (CandadoPerdidoException ex)
        {
            await _repo.FinalizarEjecucionAsync(ejecucionId, "error", ex.Message, CancellationToken.None);
            throw;
        }
        catch (Exception ex)
        {
            _log.LogError(ex, "{Fuente}/{Entidad}: falló después de {Leidos} documentos.", cfg.Codigo, e.Entidad, leidos);
            await _repo.FinalizarEjecucionAsync(ejecucionId, "error", ex.Message, CancellationToken.None);
            return false;
        }
    }

    /// <summary>Conciliación de borrados: pide todos los ids vigentes de cada proyecto y la base marca los que faltan.</summary>
    private async Task ConciliarAsync(ConfiguracionFuente cfg, IJiraCliente jira, CancellationToken ct)
    {
        var eIssue = cfg.Entidades.FirstOrDefault(e => e.Entidad == "issue");
        if (eIssue is null) return;
        var ejecucionId = await _repo.IniciarEjecucionAsync(cfg.Codigo, "issue", "conciliacion", Propietario, _op.DuracionCandadoSegundos, ct);
        try
        {
            var total = 0;
            foreach (var p in cfg.Proyectos)
            {
                var ids = new List<string>();
                string? token = null;
                do
                {
                    var url = $"{eIssue.Endpoint}?jql={Uri.EscapeDataString(Jql.Proyecto(p.Clave))}&fields=id&maxResults=5000"
                              + (token is null ? "" : $"&nextPageToken={Uri.EscapeDataString(token)}");
                    using var doc = await jira.GetAsync(url, ct);
                    if (doc.RootElement.TryGetProperty("issues", out var arr))
                        ids.AddRange(arr.EnumerateArray().Select(i => i.GetProperty("id").GetString()!));
                    token = doc.RootElement.TryGetProperty("nextPageToken", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() : null;
                } while (token is not null);
                total += await _repo.ConciliarIdsAsync(ejecucionId, p.ProyectoId, ids, ct);
            }
            await _repo.FinalizarEjecucionAsync(ejecucionId, "ok", $"{total} issues marcados como eliminados.", CancellationToken.None);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            await _repo.FinalizarEjecucionAsync(ejecucionId, "error", "Cancelado al detener el servicio.", CancellationToken.None);
            throw;
        }
        catch (Exception ex)
        {
            _log.LogError(ex, "{Fuente}: falló la conciliación.", cfg.Codigo);
            await _repo.FinalizarEjecucionAsync(ejecucionId, "error", ex.Message, CancellationToken.None);
        }
    }

    /// <summary>
    /// Le toca a una entidad si nunca corrió, si ya pasó su frecuencia desde la última vez que terminó bien,
    /// o, si el último intento falló, cuando ya pasó MinutosReintentoTrasError (no se insiste cada minuto contra un Jira caído).
    /// </summary>
    internal bool Vencida(EntidadConfig e)
    {
        var ahora = _tiempo.GetUtcNow();
        if (e.UltimoIntento is null) return true;
        if (e.UltimoEstado is not ("ok" or "parcial"))
            return ahora - e.UltimoIntento.Value >= TimeSpan.FromMinutes(_op.MinutosReintentoTrasError);
        return e.UltimaOk is null || ahora - e.UltimaOk.Value >= TimeSpan.FromMinutes(e.FrecuenciaMin);
    }

    private bool ConciliacionVencida(ConfiguracionFuente cfg)
    {
        var ahora = _tiempo.GetUtcNow();
        return _op.ConciliacionCadaHoras > 0 && cfg.Proyectos.Count > 0
            && (cfg.UltimaConciliacion is null || ahora - cfg.UltimaConciliacion.Value >= TimeSpan.FromHours(_op.ConciliacionCadaHoras))
            && (cfg.UltimoIntentoConciliacion is null || ahora - cfg.UltimoIntentoConciliacion.Value >= TimeSpan.FromMinutes(_op.MinutosReintentoTrasError));
    }
}
