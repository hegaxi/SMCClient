using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace SMCClient.Api.Procedimientos;

public interface IEjecutorProcedimientos
{
    Task<ResultadoEjecucion> EjecutarAsync(ProcedimientoInfo proc, JsonElement? cuerpo, string usuario, CancellationToken ct);
}

/// <summary>
/// Ejecuta un procedimiento del esquema api ya validado contra el catálogo. El nombre se toma de los metadatos
/// (nunca del texto del cliente) y cada valor viaja como parámetro tipado.
/// Errores de negocio: THROW 50000-59999 llegan al usuario con su mensaje. Si los tres últimos dígitos son un
/// código HTTP 4xx (p. ej. 50404) se usa ese estado; si no, 400.
/// </summary>
public sealed class EjecutorProcedimientos(ConexionSql conexion, IOptions<ApiOptions> opciones, ILogger<EjecutorProcedimientos> log) : IEjecutorProcedimientos
{
    public async Task<ResultadoEjecucion> EjecutarAsync(ProcedimientoInfo proc, JsonElement? cuerpo, string usuario, CancellationToken ct)
    {
        var valores = LeerCuerpo(cuerpo);
        var parametros = Parametros(proc, valores, usuario);

        await using var cn = await conexion.AbrirAsync(ct);
        await using var cmd = new SqlCommand("api." + Corchetes(proc.Nombre), cn)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = opciones.Value.TimeoutSqlSegundos,
        };
        cmd.Parameters.AddRange(parametros.ToArray());

        var resultados = new List<ConjuntoResultados>();
        try
        {
            await using var r = await cmd.ExecuteReaderAsync(ct);
            do
            {
                if (r.FieldCount == 0) continue;
                resultados.Add(await LeerConjuntoAsync(r, opciones.Value.MaxFilas, ct));
            } while (await r.NextResultAsync(ct));
        }
        catch (SqlException ex) when (ex.Number is >= 50000 and <= 59999)
        {
            var http = ex.Number % 1000;
            throw new ErrorProcedimientoException(http is >= 400 and <= 499 ? http : 400, $"sql.{ex.Number}", ex.Message);
        }
        catch (SqlException ex) when (ex.Number == -2)
        {
            throw new ErrorProcedimientoException(504, "sql.timeout", "La consulta tardó demasiado. Pruebe con filtros más específicos.");
        }
        catch (SqlException ex)
        {
            log.LogError(ex, "Error de SQL Server al ejecutar api.{Procedimiento}.", proc.Nombre);
            throw new ErrorProcedimientoException(500, "sql.error", "Error al consultar la base de datos.");
        }

        var salida = parametros.Where(p => p.Direction != ParameterDirection.Input)
            .ToDictionary(p => p.ParameterName.TrimStart('@'), p => p.Value is DBNull ? null : p.Value);
        return new ResultadoEjecucion("api." + proc.Nombre, resultados, salida);
    }

    private static Dictionary<string, JsonElement> LeerCuerpo(JsonElement? cuerpo)
    {
        var valores = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        if (cuerpo is null || cuerpo.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return valores;
        if (cuerpo.Value.ValueKind != JsonValueKind.Object)
            throw new ErrorProcedimientoException(400, "cuerpo.invalido", "El cuerpo debe ser un objeto JSON con los parámetros: {\"Proyecto\":\"SMC26\"}.");
        foreach (var p in cuerpo.Value.EnumerateObject()) valores[p.Name.TrimStart('@')] = p.Value;
        return valores;
    }

    private static List<SqlParameter> Parametros(ProcedimientoInfo proc, Dictionary<string, JsonElement> valores, string usuario)
    {
        var errores = new Dictionary<string, string[]>();
        var conocidos = proc.Parametros.Select(p => p.Nombre).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var nombre in valores.Keys.Where(k => !conocidos.Contains(k)))
            errores[nombre] = new[] { "El procedimiento no tiene este parámetro." };
        foreach (var p in proc.Parametros.Where(p => !p.Opcional && !p.Salida && !valores.ContainsKey(p.Nombre)))
            errores[p.Nombre] = new[] { "Es obligatorio." };
        if (errores.Count > 0)
            throw new ErrorProcedimientoException(400, "parametro.invalido", "Hay parámetros faltantes o desconocidos.", errores);

        var lista = new List<SqlParameter>();
        foreach (var p in proc.Parametros)
        {
            // Los opcionales que no se envían no se agregan: el procedimiento usa su valor por omisión.
            if (valores.TryGetValue(p.Nombre, out var v)) lista.Add(ConversorParametros.Crear(p, v));
            else if (p.Salida) lista.Add(ConversorParametros.Crear(p, null));
        }
        foreach (var p in proc.ParametrosDeContexto)
            lista.Add(ConversorParametros.Crear(p, JsonSerializer.SerializeToElement(usuario)));
        return lista;
    }

    private static async Task<ConjuntoResultados> LeerConjuntoAsync(SqlDataReader r, int maxFilas, CancellationToken ct)
    {
        var columnas = new List<ColumnaInfo>();
        var nombres = new List<string>();
        var usados = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < r.FieldCount; i++)
        {
            var nombre = string.IsNullOrEmpty(r.GetName(i)) ? $"Columna{i + 1}" : r.GetName(i);
            var unico = nombre;
            for (var n = 2; !usados.Add(unico); n++) unico = $"{nombre}_{n}";
            nombres.Add(unico);
            columnas.Add(new ColumnaInfo(unico, r.GetDataTypeName(i), true));
        }

        var filas = new List<Dictionary<string, object?>>();
        var truncado = false;
        while (await r.ReadAsync(ct))
        {
            if (filas.Count >= maxFilas) { truncado = true; break; }
            var fila = new Dictionary<string, object?>(r.FieldCount);
            for (var i = 0; i < r.FieldCount; i++) fila[nombres[i]] = r.IsDBNull(i) ? null : r.GetValue(i);
            filas.Add(fila);
        }
        return new ConjuntoResultados(columnas, filas, truncado);
    }

    private static string Corchetes(string nombre) => "[" + nombre.Replace("]", "]]") + "]";
}
