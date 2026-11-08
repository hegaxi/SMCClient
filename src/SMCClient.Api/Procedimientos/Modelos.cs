namespace SMCClient.Api.Procedimientos;

/// <summary>Metadatos de un procedimiento del esquema api, tal como los ve la interfaz.</summary>
public sealed record ProcedimientoInfo(
    string Nombre,
    string? Descripcion,
    string Permiso,
    bool ExentoSync,
    IReadOnlyList<ParametroInfo> Parametros,
    IReadOnlyList<ColumnaInfo>? Columnas,
    IReadOnlyList<string>? TitulosResultados,
    string Titulo,
    bool Accion,
    bool Oculto = false)
{
    /// <summary>Parámetros que llena el servidor (usuario autenticado); no se exponen ni se aceptan del cliente.</summary>
    internal IReadOnlyList<ParametroInfo> ParametrosDeContexto { get; init; } = Array.Empty<ParametroInfo>();
}

/// <param name="Nombre">Sin la arroba: "Proyecto".</param>
/// <param name="Tipo">Tipo de SQL Server: int, varchar, date, datetimeoffset...</param>
/// <param name="Longitud">Caracteres para texto (-1 = max); null para otros tipos.</param>
/// <param name="Opcional">El procedimiento declara un valor por omisión: se puede omitir.</param>
/// <param name="Opciones">Valores permitidos (propiedad extendida smc:opciones): la interfaz muestra una lista.</param>
public sealed record ParametroInfo(
    string Nombre, string Tipo, int? Longitud, byte? Precision, byte? Escala, bool Opcional, bool Salida, string? Descripcion,
    IReadOnlyList<OpcionParametro>? Opciones = null);

public sealed record OpcionParametro(string Valor, string Etiqueta);

public sealed record ColumnaInfo(string Nombre, string Tipo, bool Nulo);

/// <summary>Resultado de ejecutar un procedimiento: uno o varios conjuntos de filas y los parámetros de salida.</summary>
public sealed record ResultadoEjecucion(string Procedimiento, IReadOnlyList<ConjuntoResultados> Resultados, IReadOnlyDictionary<string, object?> Salida);

public sealed record ConjuntoResultados(IReadOnlyList<ColumnaInfo> Columnas, IReadOnlyList<Dictionary<string, object?>> Filas, bool Truncado);

/// <summary>Error que se devuelve al usuario como ProblemDetails (400, 404, 409...).</summary>
public sealed class ErrorProcedimientoException(int estadoHttp, string codigo, string mensaje, IDictionary<string, string[]>? errores = null)
    : Exception(mensaje)
{
    public int EstadoHttp { get; } = estadoHttp;
    public string Codigo { get; } = codigo;
    public IDictionary<string, string[]>? Errores { get; } = errores;
}
