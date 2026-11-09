using System.Data;
using Microsoft.Data.SqlClient;
using SMCClient.Api.Procedimientos;

namespace SMCClient.Api.Seguridad;

public sealed record ResultadoInicio(string Resultado, string? Nombre, Guid? Sello, bool DebeCambiar);

public sealed record PermisosUsuario(bool Valido, bool DebeCambiar, IReadOnlySet<string> Procedimientos);

public sealed record DatosUsuario(string Login, string Nombre, string? Roles, bool EsAdministrador, bool PuedeRestablecerContrasena);

/// <summary>Llamadas a los procedimientos seg.* de sesión y autorización. Las reglas están en SQL Server.</summary>
public sealed class RepositorioSesion(ConexionSql conexion)
{
    public async Task<HashContrasena?> CredencialAsync(string login, CancellationToken ct)
    {
        await using var cn = await conexion.AbrirAsync(ct);
        await using var cmd = Proc(cn, "seg.Login_Credencial");
        cmd.Parameters.Add(new SqlParameter("@Login", SqlDbType.NVarChar, 100) { Value = login });
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? new HashContrasena((byte[])r[0], (byte[])r[1], r.GetInt32(2)) : null;
    }

    public async Task<ResultadoInicio> RegistrarInicioAsync(string login, bool coincide, string? origen, CancellationToken ct)
    {
        await using var cn = await conexion.AbrirAsync(ct);
        await using var cmd = Proc(cn, "seg.Login_Resultado");
        cmd.Parameters.Add(new SqlParameter("@Login", SqlDbType.NVarChar, 100) { Value = login });
        cmd.Parameters.Add(new SqlParameter("@Coincide", SqlDbType.Bit) { Value = coincide });
        cmd.Parameters.Add(new SqlParameter("@Origen", SqlDbType.NVarChar, 100) { Value = (object?)origen ?? DBNull.Value });
        await using var r = await cmd.ExecuteReaderAsync(ct);
        await r.ReadAsync(ct);
        return new ResultadoInicio(r.GetString(0), r.IsDBNull(1) ? null : r.GetString(1),
                                   r.IsDBNull(2) ? null : r.GetGuid(2), !r.IsDBNull(3) && r.GetBoolean(3));
    }

    /// <summary>Devuelve el sello nuevo. Errores de regla (50400/50403/50404) llegan como ErrorProcedimientoException.</summary>
    public async Task<Guid> EstablecerContrasenaAsync(string login, HashContrasena hash, int longitud, string usuarioActual, bool actualVerificada, CancellationToken ct)
    {
        await using var cn = await conexion.AbrirAsync(ct);
        await using var cmd = Proc(cn, "seg.Contrasena_Establecer");
        cmd.Parameters.Add(new SqlParameter("@Login", SqlDbType.NVarChar, 100) { Value = login });
        cmd.Parameters.Add(new SqlParameter("@Hash", SqlDbType.VarBinary, 64) { Value = hash.Hash });
        cmd.Parameters.Add(new SqlParameter("@Sal", SqlDbType.VarBinary, 32) { Value = hash.Sal });
        cmd.Parameters.Add(new SqlParameter("@Iteraciones", SqlDbType.Int) { Value = hash.Iteraciones });
        cmd.Parameters.Add(new SqlParameter("@Longitud", SqlDbType.Int) { Value = longitud });
        cmd.Parameters.Add(new SqlParameter("@UsuarioActual", SqlDbType.NVarChar, 100) { Value = usuarioActual });
        cmd.Parameters.Add(new SqlParameter("@ActualVerificada", SqlDbType.Bit) { Value = actualVerificada });
        var sello = cmd.Parameters.Add(new SqlParameter("@SelloNuevo", SqlDbType.UniqueIdentifier) { Direction = ParameterDirection.Output });
        try
        {
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (SqlException ex) when (ex.Number is >= 50000 and <= 59999)
        {
            var http = ex.Number % 1000;
            throw new ErrorProcedimientoException(http is >= 400 and <= 499 ? http : 400, $"sql.{ex.Number}", ex.Message);
        }
        return (Guid)sello.Value;
    }

    public async Task<PermisosUsuario> PermisosAsync(string login, Guid? sello, CancellationToken ct)
    {
        await using var cn = await conexion.AbrirAsync(ct);
        await using var cmd = Proc(cn, "seg.Permisos_Usuario");
        cmd.Parameters.Add(new SqlParameter("@Login", SqlDbType.NVarChar, 100) { Value = login });
        cmd.Parameters.Add(new SqlParameter("@Sello", SqlDbType.UniqueIdentifier) { Value = (object?)sello ?? DBNull.Value });
        var valido = cmd.Parameters.Add(new SqlParameter("@Valido", SqlDbType.Bit) { Direction = ParameterDirection.Output });
        var cambiar = cmd.Parameters.Add(new SqlParameter("@DebeCambiar", SqlDbType.Bit) { Direction = ParameterDirection.Output });
        var procs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using (var r = await cmd.ExecuteReaderAsync(ct))
            while (await r.ReadAsync(ct)) procs.Add(r.GetString(0));
        return new PermisosUsuario(valido.Value is true, cambiar.Value is true, procs);
    }

    public async Task<DatosUsuario?> UsuarioAsync(string login, CancellationToken ct)
    {
        await using var cn = await conexion.AbrirAsync(ct);
        await using var cmd = Proc(cn, "api.Mi_Usuario");
        cmd.Parameters.Add(new SqlParameter("@UsuarioActual", SqlDbType.NVarChar, 200) { Value = login });
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct)
            ? new DatosUsuario(r.GetString(0), r.GetString(1), r.IsDBNull(2) ? null : r.GetString(2), r.GetBoolean(3), !r.IsDBNull(4) && r.GetBoolean(4))
            : null;
    }

    private static SqlCommand Proc(SqlConnection cn, string nombre) => new(nombre, cn) { CommandType = CommandType.StoredProcedure };
}
