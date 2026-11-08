namespace SMCClient.Sync.Datos;

/// <summary>Documento JSON tal como llegó de Jira, listo para raw.Documento.</summary>
public sealed record DocumentoJira(string IdExterno, DateTimeOffset? Actualizado, string Json);

public sealed record EntidadConfig(
    string Entidad, int Orden, string Modo, int FrecuenciaMin, string Endpoint, int TamanoLote,
    string? Parametros, DateTimeOffset? UltimaOk, DateTimeOffset? UltimoIntento = null, string? UltimoEstado = null);

public sealed record ProyectoVigente(string ProyectoId, string Clave, string? TipoProyecto);

public sealed record ConfiguracionFuente(
    int FuenteId, string Codigo, string UrlBase, DateTimeOffset? UltimaConciliacion,
    IReadOnlyList<EntidadConfig> Entidades, IReadOnlyList<string> ProyectosExcluidos, IReadOnlyList<ProyectoVigente> Proyectos,
    DateTimeOffset? UltimoIntentoConciliacion = null);

public sealed record MarcaAgua(DateTimeOffset? Valor, DateTimeOffset Desde, bool EsCargaInicial);

public sealed record SolicitudSync(long SolicitudId, string? Fuente, string? Entidad, string Modo, string? Parametros);

/// <summary>Otra instancia tiene vigente el candado de la fuente (error 50010 de sync.Ejecucion_Iniciar).</summary>
public sealed class CandadoOcupadoException(string fuente, Exception interna)
    : Exception($"Otra instancia está sincronizando la fuente '{fuente}'.", interna);

/// <summary>El candado expiró y lo tomó otra instancia durante una carga: hay que detenerse.</summary>
public sealed class CandadoPerdidoException(string fuente)
    : Exception($"Se perdió el candado de la fuente '{fuente}'.");
