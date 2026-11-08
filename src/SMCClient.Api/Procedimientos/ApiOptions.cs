namespace SMCClient.Api.Procedimientos;

/// <summary>Sección "Api" de appsettings.</summary>
public sealed class ApiOptions
{
    public const string Seccion = "Api";

    /// <summary>Segundos que se reutilizan los metadatos antes de verificar si cambiaron (0 = siempre verificar).</summary>
    public int SegundosCacheMetadatos { get; set; } = 30;

    /// <summary>Segundos que se reutiliza el resultado de api.Sync_Estado para la compuerta de sincronización.</summary>
    public int SegundosCacheEstadoSync { get; set; } = 5;

    /// <summary>Tiempo máximo de un procedimiento.</summary>
    public int TimeoutSqlSegundos { get; set; } = 60;

    /// <summary>Filas máximas por conjunto de resultados (protege a la API y al navegador).</summary>
    public int MaxFilas { get; set; } = 10_000;

    /// <summary>
    /// Parámetros que llena el servidor con el usuario autenticado y que el cliente no puede enviar
    /// (p. ej. @SolicitadoPor de api.Sync_Solicitar). Evita que alguien se haga pasar por otro.
    /// </summary>
    public List<string> ParametrosDeUsuario { get; set; } = new() { "SolicitadoPor" };

    /// <summary>Hospeda también el worker de sincronización dentro de la API (si no, corre como servicio aparte).</summary>
    public bool HospedarWorker { get; set; }
}
