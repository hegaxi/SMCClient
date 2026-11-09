using System.Data;
using System.Globalization;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace SMCClient.Api.Procedimientos;

/// <summary>Convierte los valores JSON del cliente al tipo exacto de cada parámetro (nunca se arma SQL con texto).</summary>
internal static class ConversorParametros
{
    public static SqlParameter Crear(ParametroInfo p, JsonElement? valor)
    {
        var sql = new SqlParameter("@" + p.Nombre, TipoSql(p.Tipo))
        {
            Direction = p.Salida ? ParameterDirection.InputOutput : ParameterDirection.Input,
        };
        if (p.Longitud is { } l) sql.Size = l;
        if (p.Precision is { } pr) sql.Precision = pr;
        if (p.Escala is { } es) sql.Scale = es;
        sql.Value = valor is null || valor.Value.ValueKind == JsonValueKind.Null ? DBNull.Value : Convertir(p, valor.Value);
        return sql;
    }

    private static object Convertir(ParametroInfo p, JsonElement v)
    {
        try
        {
            object r = p.Tipo switch
            {
                "varchar" or "nvarchar" or "char" or "nchar" => Texto(p, v),
                "bit" => v.ValueKind switch
                {
                    JsonValueKind.True => true,
                    JsonValueKind.False => false,
                    JsonValueKind.Number => v.GetInt32() != 0,
                    _ => bool.Parse(v.GetString()!),
                },
                "tinyint" => checked((byte)Entero(v)),
                "smallint" => checked((short)Entero(v)),
                "int" => checked((int)Entero(v)),
                "bigint" => Entero(v),
                "decimal" or "numeric" or "money" or "smallmoney" =>
                    v.ValueKind == JsonValueKind.Number ? v.GetDecimal() : decimal.Parse(v.GetString()!, NumberStyles.Number, CultureInfo.InvariantCulture),
                "float" or "real" =>
                    v.ValueKind == JsonValueKind.Number ? v.GetDouble() : double.Parse(v.GetString()!, NumberStyles.Float, CultureInfo.InvariantCulture),
                "date" => DateOnly.ParseExact(v.GetString()!, "yyyy-MM-dd", CultureInfo.InvariantCulture).ToDateTime(TimeOnly.MinValue),
                "datetime" or "datetime2" or "smalldatetime" => DateTime.Parse(v.GetString()!, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind),
                "datetimeoffset" => DateTimeOffset.Parse(v.GetString()!, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind),
                "uniqueidentifier" => Guid.Parse(v.GetString()!),
                _ => throw new FormatException($"tipo {p.Tipo} no soportado por la API"),
            };
            return r;
        }
        catch (Exception ex) when (ex is FormatException or InvalidOperationException or OverflowException or ArgumentNullException)
        {
            throw new ErrorProcedimientoException(400, "parametro.invalido", "Hay parámetros con valores inválidos.",
                new Dictionary<string, string[]> { [p.Nombre] = new[] { $"Se esperaba un valor de tipo {p.Tipo}." } });
        }
    }

    private static long Entero(JsonElement v) =>
        v.ValueKind == JsonValueKind.Number ? v.GetInt64() : long.Parse(v.GetString()!, NumberStyles.Integer, CultureInfo.InvariantCulture);

    private static string Texto(ParametroInfo p, JsonElement v)
    {
        var s = v.ValueKind switch
        {
            JsonValueKind.String => v.GetString()!,
            JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False => v.GetRawText(),
            _ => throw new FormatException(),
        };
        if (p.Longitud is > 0 and var max && s.Length > max)
            throw new ErrorProcedimientoException(400, "parametro.invalido", "Hay parámetros con valores inválidos.",
                new Dictionary<string, string[]> { [p.Nombre] = new[] { $"Máximo {max} caracteres." } });
        return s;
    }

    private static SqlDbType TipoSql(string tipo) => tipo switch
    {
        "varchar" => SqlDbType.VarChar,
        "nvarchar" => SqlDbType.NVarChar,
        "char" => SqlDbType.Char,
        "nchar" => SqlDbType.NChar,
        "bit" => SqlDbType.Bit,
        "tinyint" => SqlDbType.TinyInt,
        "smallint" => SqlDbType.SmallInt,
        "int" => SqlDbType.Int,
        "bigint" => SqlDbType.BigInt,
        "decimal" or "numeric" => SqlDbType.Decimal,
        "money" => SqlDbType.Money,
        "smallmoney" => SqlDbType.SmallMoney,
        "float" => SqlDbType.Float,
        "real" => SqlDbType.Real,
        "date" => SqlDbType.Date,
        "datetime" => SqlDbType.DateTime,
        "datetime2" => SqlDbType.DateTime2,
        "smalldatetime" => SqlDbType.SmallDateTime,
        "datetimeoffset" => SqlDbType.DateTimeOffset,
        "uniqueidentifier" => SqlDbType.UniqueIdentifier,
        _ => SqlDbType.Variant,
    };
}
