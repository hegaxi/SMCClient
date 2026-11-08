using System.Text.Json;
using SMCClient.Api;
using SMCClient.Api.Procedimientos;
using SMCClient.Api.Seguridad;
using SMCClient.Api.Sincronizacion;
using SMCClient.Sync;

var builder = WebApplication.CreateBuilder(args);

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
app.UseStaticFiles();          // aquí se publicará el build de React (wwwroot)
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/salud").AllowAnonymous();

app.Run();

public partial class Program;
