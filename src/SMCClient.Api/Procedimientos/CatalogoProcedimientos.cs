using System.Data;
using System.Text.Json;
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
/// (MS_Description, smc:permiso, smc:exentoSync, smc:titulo, smc:accion, smc:oculto, smc:menu, smc:orden, smc:padre, smc:acciones…). Se guarda en memoria y se recarga solo cuando cambia
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
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:accion') AS nvarchar(10)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:oculto') AS nvarchar(10)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:menu') AS nvarchar(200)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:orden') AS nvarchar(20)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:padre') AS nvarchar(128)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:acciones') AS nvarchar(3750)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:columnasSecundarias') AS nvarchar(1000)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 1 AND major_id = p.object_id AND minor_id = 0 AND name = 'smc:ayudaColumnas') AS nvarchar(3750))
        FROM sys.procedures p
        WHERE p.schema_id = SCHEMA_ID('api')
        ORDER BY p.name;

        SELECT pa.object_id, pa.name, TYPE_NAME(pa.system_type_id), pa.max_length, pa.precision, pa.scale, pa.is_output,
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'MS_Description') AS nvarchar(3750)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'smc:opciones') AS nvarchar(3750)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'smc:origen') AS nvarchar(400)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'smc:multiple') AS nvarchar(10)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'smc:origenLibre') AS nvarchar(10)),
               CAST((SELECT value FROM sys.extended_properties WHERE class = 2 AND major_id = pa.object_id AND minor_id = pa.parameter_id AND name = 'smc:inicial') AS nvarchar(30))
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

        var procs = new List<(int Id, string Nombre, string? Descripcion, string Permiso, bool Exento, string Definicion, string? Resultados, string Titulo, bool Accion, bool Oculto, string? Menu, int? Orden, string? Padre, string? Acciones, string? Secundarias, string? Ayuda)>();
        while (await r.ReadAsync(ct))
        {
            procs.Add((r.GetInt32(0), r.GetString(1), r.IsDBNull(2) ? null : r.GetString(2),
                       r.IsDBNull(3) ? "admin" : r.GetString(3).Trim().ToLowerInvariant(),   // sin permiso declarado: solo administradores
                       !r.IsDBNull(4) && r.GetString(4).Trim() == "1",
                       r.IsDBNull(5) ? "" : r.GetString(5),
                       r.IsDBNull(6) ? null : r.GetString(6),
                       r.IsDBNull(7) ? r.GetString(1).Replace('_', ' ') : r.GetString(7),
                       !r.IsDBNull(8) && r.GetString(8).Trim() == "1",
                       !r.IsDBNull(9) && r.GetString(9).Trim() == "1",
                       r.IsDBNull(10) ? null : r.GetString(10).Trim(),
                       !r.IsDBNull(11) && int.TryParse(r.GetString(11), out var orden) ? orden : null,
                       r.IsDBNull(12) ? null : r.GetString(12).Trim(),
                       r.IsDBNull(13) ? null : r.GetString(13),
                       r.IsDBNull(14) ? null : r.GetString(14),
                       r.IsDBNull(15) ? null : r.GetString(15)));
        }

        await r.NextResultAsync(ct);
        var parametros = new Dictionary<int, List<(string Nombre, string Tipo, short MaxLen, byte Prec, byte Escala, bool Salida, string? Desc, string? Opciones, string? Origen, string? Multiple, bool Libre, string? Inicial)>>();
        while (await r.ReadAsync(ct))
        {
            var id = r.GetInt32(0);
            if (!parametros.TryGetValue(id, out var lista)) parametros[id] = lista = new();
            lista.Add((r.GetString(1).TrimStart('@'), r.GetString(2), r.GetInt16(3), r.GetByte(4), r.GetByte(5), r.GetBoolean(6),
                       r.IsDBNull(7) ? null : r.GetString(7), r.IsDBNull(8) ? null : r.GetString(8),
                       r.IsDBNull(9) ? null : r.GetString(9), r.IsDBNull(10) ? null : r.GetString(10),
                       !r.IsDBNull(11) && r.GetString(11).Trim() == "1",
                       r.IsDBNull(12) ? null : r.GetString(12).Trim()));
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
            var conDefault = ValoresPorOmision(p.Definicion);
            var todos = (parametros.GetValueOrDefault(p.Id) ?? new()).Select(x => new ParametroInfo(
                x.Nombre, x.Tipo,
                EsTexto(x.Tipo) ? (x.MaxLen == -1 ? -1 : x.Tipo.StartsWith('n') ? x.MaxLen / 2 : x.MaxLen) : null,
                EsDecimal(x.Tipo) ? x.Prec : null, EsDecimal(x.Tipo) ? x.Escala : null,
                conDefault.ContainsKey(x.Nombre), x.Salida, x.Desc, Opciones(x.Opciones),
                Origen(x.Origen, x.Libre), string.IsNullOrEmpty(x.Multiple) ? null : x.Multiple,
                conDefault.GetValueOrDefault(x.Nombre), string.IsNullOrEmpty(x.Inicial) ? null : x.Inicial)).ToList();

            resultado[p.Nombre] = new ProcedimientoInfo(
                p.Nombre, p.Descripcion, p.Permiso, p.Exento,
                todos.Where(x => !deUsuario.Contains(x.Nombre)).ToList(),
                columnas.GetValueOrDefault(p.Id),
                p.Resultados?.Split('|', StringSplitOptions.TrimEntries),
                p.Titulo,
                p.Accion,
                p.Oculto,
                p.Menu,
                p.Orden,
                p.Padre,
                Acciones(p.Nombre, p.Acciones),
                p.Secundarias?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries),
                AyudaColumnas(p.Nombre, p.Ayuda))
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
    internal static HashSet<string> ParametrosConValorPorOmision(string definicion) =>
        ValoresPorOmision(definicion).Keys.ToHashSet(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Parámetros con valor por omisión y ese valor como texto: "@Nivel varchar(10) = 'tarea'" -> tarea; "= 1" -> 1;
    /// "= NULL" -> null. La interfaz lo muestra en la opción vacía ("Sí (por omisión)").
    /// </summary>
    internal static Dictionary<string, string?> ValoresPorOmision(string definicion)
    {
        var sinComentarios = Comentarios().Replace(definicion, " ");
        var m = Encabezado().Match(sinComentarios);
        var encabezado = m.Success ? m.Groups[1].Value : "";
        var res = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        foreach (Match x in Parametro().Matches(encabezado))
        {
            var resto = x.Groups[2].Value;
            var i = resto.IndexOf('=');
            if (i < 0) continue;
            var v = SufijoParametro().Replace(resto[(i + 1)..], "").Trim();
            if (v.Length > 1 && (v[0] == 'N' || v[0] == 'n') && v[1] == '\'') v = v[1..];
            res[x.Groups[1].Value] = v.Equals("NULL", StringComparison.OrdinalIgnoreCase) ? null
                : v.Length >= 2 && v[0] == '\'' && v[^1] == '\'' ? v[1..^1].Replace("''", "'") : v;
        }
        return res;
    }

    /// <summary>smc:ayudaColumnas = {"Columna": "qué significa"}: la interfaz lo muestra al pasar sobre el encabezado.</summary>
    private IReadOnlyDictionary<string, string>? AyudaColumnas(string procedimiento, string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<Dictionary<string, string>>(json); }
        catch (JsonException) { log.LogWarning("smc:ayudaColumnas de {Procedimiento} no es un objeto JSON válido; se ignora.", procedimiento); return null; }
    }

    /// <summary>smc:opciones = "software=Scrum|service_desk=Mesa de ayuda" (la etiqueta es opcional).</summary>
    internal static IReadOnlyList<OpcionParametro>? Opciones(string? valor) =>
        string.IsNullOrWhiteSpace(valor) ? null : valor.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(o => o.Split('=', 2, StringSplitOptions.TrimEntries))
            .Select(o => new OpcionParametro(o[0], o.Length > 1 ? o[1] : o[0]))
            .ToList();

    /// <summary>
    /// smc:origen = "Procedimiento:ColumnaValor[:ColumnaEtiqueta[:ColumnaDescripcion]]": la interfaz ejecuta ese procedimiento
    /// del esquema api (con los permisos del usuario) y ofrece sus filas como lista. Sin etiqueta se muestra el valor.
    /// </summary>
    internal static OrigenParametro? Origen(string? valor, bool libre)
    {
        if (string.IsNullOrWhiteSpace(valor)) return null;
        var partes = valor.Split(':', StringSplitOptions.TrimEntries);
        if (partes.Length < 2 || partes[0] == "" || partes[1] == "") return null;
        string? Parte(int i) => partes.Length > i && partes[i] != "" ? partes[i] : null;
        // "Sprints_Listar(Proyecto=@Proyecto)": parámetros del origen; @Campo = valor de ese campo del formulario.
        var m = OrigenConParametros().Match(partes[0]);
        if (!m.Success) return null;
        var parametros = m.Groups[2].Success
            ? m.Groups[2].Value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(x => x.Split('=', 2, StringSplitOptions.TrimEntries)).Where(x => x.Length == 2 && x[0] != "")
                .ToDictionary(x => x[0], x => x[1], StringComparer.OrdinalIgnoreCase)
            : null;
        return new OrigenParametro(m.Groups[1].Value, partes[1], Parte(2), Parte(3), libre, parametros);
    }

    [GeneratedRegex(@"^(\w+)(?:\((.*)\))?$")]
    private static partial Regex OrigenConParametros();

    /// <summary>
    /// smc:acciones (en un listado): JSON con los botones "Nuevo" y las acciones de cada fila (ver
    /// db/11_DatosSemilla/093_Acciones.sql). Se valida que sea un arreglo JSON; si no, se ignora y se avisa en el log.
    /// </summary>
    private JsonElement? Acciones(string procedimiento, string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind == JsonValueKind.Array) return doc.RootElement.Clone();
        }
        catch (JsonException) { }
        log.LogWarning("smc:acciones de {Procedimiento} no es un arreglo JSON válido; se ignora.", procedimiento);
        return null;
    }

    private static bool EsTexto(string tipo) => tipo is "varchar" or "nvarchar" or "char" or "nchar";
    private static bool EsDecimal(string tipo) => tipo is "decimal" or "numeric";

    [GeneratedRegex(@"--[^\r\n]*|/\*.*?\*/", RegexOptions.Singleline)]
    private static partial Regex Comentarios();

    [GeneratedRegex(@"\s+(OUTPUT|OUT|READONLY)\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex SufijoParametro();

    [GeneratedRegex(@"CREATE\s+(?:OR\s+ALTER\s+)?PROC(?:EDURE)?\s+[^\s(]+\s*\(?(.*?)\)?\s*\bAS\b", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex Encabezado();

    // @Nombre seguido de todo lo que hay hasta la siguiente coma que no esté dentro de paréntesis ni comillas.
    [GeneratedRegex(@"@(\w+)((?:'[^']*'|\([^)]*\)|[^,'(])*)", RegexOptions.Singleline)]
    private static partial Regex Parametro();
}
