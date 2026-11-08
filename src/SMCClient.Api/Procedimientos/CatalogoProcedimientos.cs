using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace SMCClient.Api.Procedimientos;

public interface ICatalogoProcedimientos
{
    Task<IReadOnlyDictionary<string, ProcedimientoInfo>> ObtenerAsync(CancellationToken ct);
}

/// <summary>
/// Lee de SQL Server los procedimientos del esquema api: parámetros (sys.parameters), columnas del primer
/// resultado (sys.dm_exec_describe_first_result_set_for_object) y propiedades extendidas
/// (MS_Description, smc:permiso, smc:exentoSync). Se guarda en memoria y se recarga solo cuando cambia
/// algo en la base (firma = fechas de modificación + propiedades extendidas), así un procedimiento
/// nuevo aparece sin reiniciar la API.
/// </summary>
public sealed partial class CatalogoProcedimientos(ConexionSql conexion, IOptions<ApiOptions> opciones, ILogger<CatalogoProcedimientos> log)
    : ICatalogoProcedimientos
{
    private const string SqlFirma = """
        SELECT CHECKSUM_AGG(CHECKSUM(p.object_id, p.modify_date)) ^ ISNULL((SELECT CHECKSUM_AGG(CHECKSUM(ep.major_id, ep.minor_id, ep.name, CAST(ep.value AS nvarchar(3750))))
                                                                            FROM sys.extended_properties ep JOIN sys.procedures q ON q.object_id = ep.major_id
                                                                            WHERE q.schema_id = SCHEMA_ID('api') AND ep.class IN (1, 2)), 0),
               COUNT(*)
        FROM sys.procedures p WHERE p.schema_id = SCHEMA_ID('api');
        """;

    // TYPE_NAME(system_type_id): el tipo base, así sysname y los tipos alias llegan como nvarchar, etc.
    private const string SqlMetadatos = """
        SELECT p.object_id, p.name,
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'MS_Description') AS nvarchar(3750)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:permiso') AS nvarchar(50)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:exentoSync') AS nvarchar(10)),
               OBJECT_DEFINITION(p.object_id),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:resultados') AS nvarchar(3750)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:titulo') AS nvarchar(200)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:accion') AS nvarchar(10))
        FROM sys.procedures p
        WHERE p.schema_id = SCHEMA_ID('api')
        ORDER BY p.name;

        SELECT pa.object_id, pa.name, TYPE_NAME(pa.system_type_id), pa.max_length, pa.precision, pa.scale, pa.is_output,
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'MS_Description') AS nvarchar(3750)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'smc:opciones') AS nvarchar(3750))
        FROM sys.parameters pa JOIN sys.procedures p ON p.object_id = pa.object_id
        WHERE p.schema_id = SCHEMA_ID('api') AND pa.parameter_id > 0
        ORDER BY pa.object_id, pa.parameter_id;

        SELECT p.object_id, r.name, r.system_type_name, r.is_nullable
        FROM sys.procedures p
        CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(p.object_id, 0) r
        WHERE p.schema_id = SCHEMA_ID('api') AND r.error_number IS NULL AND r.is_hidden = 0
        ORDER BY p.object_id, r.column_ordinal;
        """;

    private readonly SemaphoreSlim _bloqueo = new(1, 1);
    private IReadOnlyDictionary<string, ProcedimientoInfo> _cache = new Dictionary<string, ProcedimientoInfo>();
    private (int Firma, int Cantidad)? _firma;
    private DateTimeOffset _verificado = DateTimeOffset.MinValue;

    public async Task<IReadOnlyDictionary<string, ProcedimientoInfo>> ObtenerAsync(CancellationToken ct)
    {
        if (_firma is not null && DateTimeOffset.UtcNow - _verificado < TimeSpan.FromSeconds(opciones.Value.SegundosCacheMetadatos))
            return _cache;

        await _bloqueo.WaitAsync(ct);
        try
        {
            await using var cn = await conexion.AbrirAsync(ct);
            var firma = await LeerFirmaAsync(cn, ct);
            if (firma != _firma)
            {
                _cache = await LeerMetadatosAsync(cn, ct);
                _firma = firma;
                log.LogInformation("Metadatos de la API cargados: {Cantidad} procedimientos.", _cache.Count);
            }
            _verificado = DateTimeOffset.UtcNow;
            return _cache;
        }
        finally
        {
            _bloqueo.Release();
        }
    }

    private static async Task<(int, int)> LeerFirmaAsync(SqlConnection cn, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(SqlFirma, cn);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        await r.ReadAsync(ct);
        return (r.IsDBNull(0) ? 0 : r.GetInt32(0), r.GetInt32(1));
    }

    private async Task<IReadOnlyDictionary<string, ProcedimientoInfo>> LeerMetadatosAsync(SqlConnection cn, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(SqlMetadatos, cn);
        await using var r = await cmd.ExecuteReaderAsync(ct);

        var procs = new List<(int Id, string Nombre, string? Descripcion, string Permiso, bool Exento, string Definicion, string? Resultados, string Titulo, bool Accion)>();
        while (await r.ReadAsync(ct))
        {
            procs.Add((r.GetInt32(0), r.GetString(1), r.IsDBNull(2) ? null : r.GetString(2),
                       r.IsDBNull(3) ? "admin" : r.GetString(3).Trim().ToLowerInvariant(),   // sin permiso declarado: solo administradores
                       !r.IsDBNull(4) && r.GetString(4).Trim() == "1",
                       r.IsDBNull(5) ? "" : r.GetString(5),
                       r.IsDBNull(6) ? null : r.GetString(6),
                       r.IsDBNull(7) ? r.GetString(1).Replace('_', ' ') : r.GetString(7),
                       !r.IsDBNull(8) && r.GetString(8).Trim() == "1"));
        }

        await r.NextResultAsync(ct);
        var parametros = new Dictionary<int, List<(string Nombre, string Tipo, short MaxLen, byte Prec, byte Escala, bool Salida, string? Desc, string? Opciones)>>();
        while (await r.ReadAsync(ct))
        {
            var id = r.GetInt32(0);
            if (!parametros.TryGetValue(id, out var lista)) parametros[id] = lista = new();
            lista.Add((r.GetString(1).TrimStart('@'), r.GetString(2), r.GetInt16(3), r.GetByte(4), r.GetByte(5), r.GetBoolean(6),
                       r.IsDBNull(7) ? null : r.GetString(7), r.IsDBNull(8) ? null : r.GetString(8)));
        }

        await r.NextResultAsync(ct);
        var columnas = new Dictionary<int, List<ColumnaInfo>>();
        while (await r.ReadAsync(ct))
        {
            var id = r.GetInt32(0);
            if (!columnas.TryGetValue(id, out var lista)) columnas[id] = lista = new();
            lista.Add(new ColumnaInfo(r.IsDBNull(1) ? $"Columna{lista.Count + 1}" : r.GetString(1), r.GetString(2), r.GetBoolean(3)));
        }

        var deUsuario = new HashSet<string>(opciones.Value.ParametrosDeUsuario.Select(p => p.TrimStart('@')), StringComparer.OrdinalIgnoreCase);
        var resultado = new Dictionary<string, ProcedimientoInfo>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in procs)
        {
            var conDefault = ParametrosConValorPorOmision(p.Definicion);
            var todos = (parametros.GetValueOrDefault(p.Id) ?? new()).Select(x => new ParametroInfo(
                x.Nombre, x.Tipo,
                EsTexto(x.Tipo) ? (x.MaxLen == -1 ? -1 : x.Tipo.StartsWith('n') ? x.MaxLen / 2 : x.MaxLen) : null,
                EsDecimal(x.Tipo) ? x.Prec : null, EsDecimal(x.Tipo) ? x.Escala : null,
                conDefault.Contains(x.Nombre), x.Salida, x.Desc, Opciones(x.Opciones))).ToList();

            resultado[p.Nombre] = new ProcedimientoInfo(
                p.Nombre, p.Descripcion, p.Permiso, p.Exento,
                todos.Where(x => !deUsuario.Contains(x.Nombre)).ToList(),
                columnas.GetValueOrDefault(p.Id),
                p.Resultados?.Split('|', StringSplitOptions.TrimEntries),
                p.Titulo,
                p.Accion)
            {
                ParametrosDeContexto = todos.Where(x => deUsuario.Contains(x.Nombre)).ToList(),
            };
        }
        return resultado;
    }

    /// <summary>
    /// SQL Server no guarda en el catálogo qué parámetros de un procedimiento T-SQL tienen valor por omisión,
    /// así que se lee del encabezado (entre CREATE PROCEDURE y AS): "@Proyecto varchar(50) = NULL".
    /// </summary>
    internal static HashSet<string> ParametrosConValorPorOmision(string definicion)
    {
        var sinComentarios = Comentarios().Replace(definicion, " ");
        var m = Encabezado().Match(sinComentarios);
        var encabezado = m.Success ? m.Groups[1].Value : "";
        return Parametro().Matches(encabezado)
            .Where(x => x.Groups[2].Value.Contains('='))
            .Select(x => x.Groups[1].Value)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>smc:opciones = "software=Scrum|service_desk=Mesa de ayuda" (la etiqueta es opcional).</summary>
    internal static IReadOnlyList<OpcionParametro>? Opciones(string? valor) =>
        string.IsNullOrWhiteSpace(valor) ? null : valor.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(o => o.Split('=', 2, StringSplitOptions.TrimEntries))
            .Select(o => new OpcionParametro(o[0], o.Length > 1 ? o[1] : o[0]))
            .ToList();

    private static bool EsTexto(string tipo) => tipo is "varchar" or "nvarchar" or "char" or "nchar";
    private static bool EsDecimal(string tipo) => tipo is "decimal" or "numeric";

    [GeneratedRegex(@"--[^\r\n]*|/\*.*?\*/", RegexOptions.Singleline)]
    private static partial Regex Comentarios();

    [GeneratedRegex(@"CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+[^\s(]+\s*\(?(.*?)\)?\s*\bAS\b", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex Encabezado();

    // @Nombre seguido de todo lo que hay hasta la siguiente coma que no esté dentro de paréntesis ni comillas.
    [GeneratedRegex(@"@(\w+)((?:'[^']*'|\([^)]*\)|[^,'(])*)", RegexOptions.Singleline)]
    private static partial Regex Parametro();
}
