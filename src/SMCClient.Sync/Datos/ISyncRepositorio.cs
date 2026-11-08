namespace SMCClient.Sync.Datos;

/// <summary>Acceso a los procedimientos sync.* de la base de datos.</summary>
public interface ISyncRepositorio
{
    Task<ConfiguracionFuente> ObtenerConfiguracionAsync(string fuente, CancellationToken ct);
    Task<long> IniciarEjecucionAsync(string fuente, string entidad, string modo, string propietario, int duracionCandadoSeg, CancellationToken ct);
    Task<bool> RenovarCandadoAsync(string fuente, string propietario, int duracionCandadoSeg, CancellationToken ct);
    Task LiberarCandadoAsync(string fuente, string propietario, CancellationToken ct);
    Task<MarcaAgua> ObtenerMarcaAguaAsync(string fuente, string entidad, CancellationToken ct);
    Task<int> CargarDocumentosAsync(long ejecucionId, IReadOnlyList<DocumentoJira> documentos, CancellationToken ct);
    Task<int> ProcesarPendientesAsync(int fuenteId, long ejecucionId, string entidad, CancellationToken ct);
    Task FinalizarEjecucionAsync(long ejecucionId, string estado, string? mensaje, CancellationToken ct);
    Task<SolicitudSync?> TomarSolicitudAsync(string propietario, IReadOnlyCollection<string> fuentes, CancellationToken ct);
    Task TerminarSolicitudAsync(long solicitudId, string estado, CancellationToken ct);
    Task<int> ConciliarIdsAsync(long ejecucionId, string proyectoId, IReadOnlyCollection<string> ids, CancellationToken ct);
}
