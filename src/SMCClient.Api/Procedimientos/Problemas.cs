using Microsoft.AspNetCore.Mvc;

namespace SMCClient.Api.Procedimientos;

/// <summary>Respuestas de error con ProblemDetails y un "codigo" estable que la interfaz puede interpretar.</summary>
public static class Problemas
{
    public static ObjectResult Crear(int estado, string codigo, string titulo, IDictionary<string, string[]>? errores = null,
                                     IDictionary<string, object?>? extensiones = null)
    {
        ProblemDetails pd = errores is { Count: > 0 } ? new ValidationProblemDetails(errores) : new ProblemDetails();
        pd.Status = estado;
        pd.Title = titulo;
        pd.Extensions["codigo"] = codigo;
        if (extensiones is not null) foreach (var (k, v) in extensiones) pd.Extensions[k] = v;
        return new ObjectResult(pd) { StatusCode = estado, ContentTypes = { "application/problem+json" } };
    }
}
