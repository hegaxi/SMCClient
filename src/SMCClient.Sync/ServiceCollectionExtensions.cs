using System.Net.Http.Headers;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SMCClient.Sync.Configuracion;
using SMCClient.Sync.Datos;
using SMCClient.Sync.Extractores;
using SMCClient.Sync.Jira;

namespace SMCClient.Sync;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registra la sincronización. Se puede hospedar en el Worker (servicio de Windows) o dentro de la API
    /// (hospedarWorker: true) para que sincronice al arrancar.
    /// Requiere ConnectionStrings:SMCClient y la sección SmcSync.
    /// </summary>
    public static IServiceCollection AddSmcSync(this IServiceCollection services, IConfiguration configuracion, bool hospedarWorker = true)
    {
        var seccion = configuracion.GetSection(SmcSyncOptions.Seccion);
        services.AddOptions<SmcSyncOptions>().Bind(seccion)
            .Validate(o => o.Fuentes.Count > 0, "SmcSync:Fuentes debe tener al menos una fuente.")
            .Validate(o => o.Fuentes.All(f => !string.IsNullOrWhiteSpace(f.Codigo) && Uri.TryCreate(f.UrlBase, UriKind.Absolute, out _)),
                      "Cada fuente necesita Codigo y UrlBase absoluta.")
            .Validate(o => o.Fuentes.All(f => !string.IsNullOrWhiteSpace(f.Token)),
                      "Falta el token de Jira (SmcSync:Fuentes:N:Token). Configúrelo con user-secrets o variable de entorno, no en appsettings.json.")
            .ValidateOnStart();

        var cadena = configuracion.GetConnectionString("SMCClient")
                     ?? throw new InvalidOperationException("Falta ConnectionStrings:SMCClient.");

        var opciones = seccion.Get<SmcSyncOptions>() ?? new SmcSyncOptions();
        foreach (var fuente in opciones.Fuentes)
        {
            var f = fuente;
            services.AddHttpClient(JiraClienteFactory.NombreCliente(f.Codigo), c =>
                {
                    c.BaseAddress = new Uri(f.UrlBase.TrimEnd('/') + "/");
                    c.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                    c.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("SMCClient-Sync", "1.0"));
                    c.DefaultRequestHeaders.Authorization = string.Equals(f.Autenticacion, "bearer", StringComparison.OrdinalIgnoreCase)
                        ? new AuthenticationHeaderValue("Bearer", f.Token)
                        : new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.UTF8.GetBytes($"{f.Usuario}:{f.Token}")));
                    c.Timeout = Timeout.InfiniteTimeSpan;   // los tiempos los controla el handler de resiliencia
                })
                .AddStandardResilienceHandler(r =>
                {
                    var intento = TimeSpan.FromSeconds(Math.Max(10, f.TimeoutSegundos));
                    r.AttemptTimeout.Timeout = intento;
                    r.Retry.MaxRetryAttempts = 6;                 // 429 (respetando Retry-After), 5xx y timeouts
                    r.Retry.Delay = TimeSpan.FromSeconds(2);
                    r.Retry.UseJitter = true;
                    r.CircuitBreaker.SamplingDuration = intento * 2 + TimeSpan.FromSeconds(1);
                    r.TotalRequestTimeout.Timeout = intento * 8;
                });
        }

        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IJiraClienteFactory, JiraClienteFactory>();
        services.AddSingleton<ISyncRepositorio>(sp => new SyncRepositorio(cadena, sp.GetRequiredService<IOptions<SmcSyncOptions>>().Value.TimeoutSqlSegundos));
        services.AddSingleton<IExtractor, CampoExtractor>();
        services.AddSingleton<IExtractor, EstadoExtractor>();
        services.AddSingleton<IExtractor, ProyectoExtractor>();
        services.AddSingleton<IExtractor, IssueExtractor>();
        services.AddSingleton<IExtractor, ChangelogExtractor>();
        services.AddSingleton<IExtractor, WorklogExtractor>();
        services.AddSingleton<IExtractor, WorklogEliminadoExtractor>();
        services.AddSingleton<IExtractor, SlaExtractor>();
        services.AddSingleton<IExtractor, ComentarioExtractor>();
        services.AddSingleton<Sincronizador>();
        if (hospedarWorker) services.AddHostedService<SyncWorker>();
        return services;
    }
}
