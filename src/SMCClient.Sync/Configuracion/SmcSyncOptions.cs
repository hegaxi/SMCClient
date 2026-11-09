namespace SMCClient.Sync.Configuracion;

/// <summary>Configuración del worker (sección "SmcSync" de appsettings).</summary>
public sealed class SmcSyncOptions
{
    public const string Seccion = "SmcSync";

    /// <summary>Identifica a esta instancia en el candado de la base. Por omisión: equipo:proceso.</summary>
    public string? Propietario { get; set; }

    /// <summary>Cada cuánto revisa qué entidades vencieron y si hay solicitudes pendientes.</summary>
    public int IntervaloRevisionSegundos { get; set; } = 60;

    /// <summary>Vigencia del candado por fuente; se renueva mientras una carga larga avanza.</summary>
    public int DuracionCandadoSegundos { get; set; } = 900;

    /// <summary>Después de un error (Jira caído, credenciales vencidas) espera esto antes de reintentar la entidad.</summary>
    public int MinutosReintentoTrasError { get; set; } = 5;

    /// <summary>Cada cuántas horas se concilian los issues borrados en Jira.</summary>
    public int ConciliacionCadaHoras { get; set; } = 24;

    /// <summary>Tiempo máximo de un comando SQL (la integración de una carga inicial puede tardar).</summary>
    public int TimeoutSqlSegundos { get; set; } = 600;

    /// <summary>Documentos por llamada a sync.Documento_Cargar.</summary>
    public int DocumentosPorCarga { get; set; } = 200;

    /// <summary>Solicitudes (botón "Sincronizar", backfill...) que se atienden por ciclo.</summary>
    public int MaxSolicitudesPorCiclo { get; set; } = 20;

    /// <summary>Issues pendientes de historial / SLA (sync.IssuePendiente) que se piden por corrida de cada entidad.</summary>
    public int MaxPendientesPorCorrida { get; set; } = 2000;

    /// <summary>Padres o épicas faltantes que se traen por corrida (en rondas: un padre traído puede tener su propio padre).</summary>
    public int MaxPadresPorCorrida { get; set; } = 500;

    public List<FuenteJiraOptions> Fuentes { get; set; } = new();
}

/// <summary>Una instancia de Jira. El código debe coincidir con cfg.Fuente.Codigo.</summary>
public sealed class FuenteJiraOptions
{
    public string Codigo { get; set; } = "";

    /// <summary>https://smco.atlassian.net</summary>
    public string UrlBase { get; set; } = "";

    /// <summary>basic (Jira Cloud: correo + API token) o bearer (Jira Data Center: token personal).</summary>
    public string Autenticacion { get; set; } = "basic";

    /// <summary>Correo del usuario técnico (solo lectura) para autenticación basic.</summary>
    public string? Usuario { get; set; }

    /// <summary>API token. NUNCA en appsettings.json: user-secrets, variable de entorno o almacén de secretos.</summary>
    public string? Token { get; set; }

    /// <summary>Peticiones simultáneas a Jira para los datos que se piden por issue (SLA).</summary>
    public int MaxConcurrencia { get; set; } = 4;

    /// <summary>Tiempo máximo de cada intento HTTP.</summary>
    public int TimeoutSegundos { get; set; } = 100;
}
