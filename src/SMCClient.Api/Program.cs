using System.Text.Json;
using SMCClient.Api;
using SMCClient.Api.Procedimientos;
using SMCClient.Api.Seguridad;
using SMCClient.Api.Sincronizacion;
using SMCClient.Sync;

var builder = WebApplication.CreateBuilder(args);

// Instalación: crea el primer administrador (o recupera el acceso) sin levantar el sitio.
if (args.Length > 0 && args[0] == "crear-administrador")
    return await ComandoCrearAdministrador.EjecutarAsync(args[1..], builder.Configuration);

builder.Services.Configure<ApiOptions>(builder.Configuration.GetSection(ApiOptions.Seccion));
builder.Services.AddSingleton(sp => new ConexionSql(
    sp.GetRequiredService<IConfiguration>().GetConnectionString("SMCClient")
    ?? throw new InvalidOperationException("Falta ConnectionStrings:SMCClient.")));
builder.Services.AddSingleton<ICatalogoProcedimientos, CatalogoProcedimientos>();
builder.Services.AddSingleton<IEjecutorProcedimientos, EjecutorProcedimientos>();
builder.Services.AddSingleton<ICompuertaSincronizacion, CompuertaSincronizacion>();

builder.Services.AddSeguridadSmc(builder.Configuration, builder.Environment);
builder.Services.AddControllers().AddJsonOptions(o =>
{
    o.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    o.JsonSerializerOptions.DictionaryKeyPolicy = null;   // los nombres de columna se devuelven tal cual
});
builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks().AddCheck<SaludSql>("sql");

// Opcional: el worker de sincronización dentro de la misma aplicación (en vez de un servicio aparte).
if (builder.Configuration.GetValue<bool>($"{ApiOptions.Seccion}:{nameof(ApiOptions.HospedarWorker)}"))
    builder.Services.AddSmcSync(builder.Configuration);

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseDefaultFiles();
app.UseStaticFiles();          // build de React (wwwroot): la pantalla de inicio de sesión es pública
app.UseProteccionSolicitudes();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/salud").AllowAnonymous();

app.Run();
return 0;

public partial class Program;
