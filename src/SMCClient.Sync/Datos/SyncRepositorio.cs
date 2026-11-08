using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlClient.Server;

namespace SMCClient.Sync.Datos;

/// <summary>Implementación con Microsoft.Data.SqlClient. Una conexión por llamada (usa el pool).</summary>
public sealed class SyncRepositorio(string cadenaConexion, int timeoutSegundos) : ISyncRepositorio
{
    private const int ErrorCandadoOcupado = 50010;

    private static readonly SqlMetaData[] MetaDocumento =
    {
        new("IdExterno", SqlDbType.VarChar, 100),
        new("Actualizado", SqlDbType.DateTimeOffset, 0, 3),
        new("Json", SqlDbType.NVarChar, SqlMetaData.Max),
    };

    private static readonly SqlMetaData[] MetaId = { new("IdExterno", SqlDbType.VarChar, 100) };

    public async Task<ConfiguracionFuente> ObtenerConfiguracionAsync(string fuente, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Configuracion_Obtener");
        cmd.Parameters.Add(new SqlParameter("@Fuente", SqlDbType.VarChar, 50) { Value = fuente });
        await using var r = await cmd.ExecuteReaderAsync(ct);

        if (!await r.ReadAsync(ct)) throw new InvalidOperationException($"La fuente '{fuente}' no existe en la base.");
        var fuenteId = r.GetInt32(0);
        var codigo = r.GetString(1);
        var urlBase = r.GetString(3);
        var ultimaConciliacion = r.IsDBNull(5) ? (DateTimeOffset?)null : r.GetDateTimeOffset(5);
        var intentoConciliacion = r.IsDBNull(6) ? (DateTimeOffset?)null : r.GetDateTimeOffset(6);

        await r.NextResultAsync(ct);
        var entidades = new List<EntidadConfig>();
        while (await r.ReadAsync(ct))
        {
            entidades.Add(new EntidadConfig(
                r.GetString(0), r.GetInt32(1), r.GetString(2), r.GetInt32(3), r.GetString(4), r.GetInt32(5),
                r.IsDBNull(6) ? null : r.GetString(6), r.IsDBNull(7) ? null : r.GetDateTimeOffset(7),
                r.IsDBNull(8) ? null : r.GetDateTimeOffset(8), r.IsDBNull(9) ? null : r.GetString(9)));
        }

        await r.NextResultAsync(ct);
        var excluidos = new List<string>();
        while (await r.ReadAsync(ct)) excluidos.Add(r.GetString(0));

        await r.NextResultAsync(ct);
        var proyectos = new List<ProyectoVigente>();
        while (await r.ReadAsync(ct)) proyectos.Add(new ProyectoVigente(r.GetString(0), r.GetString(1), r.IsDBNull(2) ? null : r.GetString(2)));

        return new ConfiguracionFuente(fuenteId, codigo, urlBase, ultimaConciliacion, entidades, excluidos, proyectos, intentoConciliacion);
    }

    public async Task<long> IniciarEjecucionAsync(string fuente, string entidad, string modo, string propietario, int duracionCandadoSeg, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Ejecucion_Iniciar");
        cmd.Parameters.Add(new SqlParameter("@Fuente", SqlDbType.VarChar, 50) { Value = fuente });
        cmd.Parameters.Add(new SqlParameter("@Entidad", SqlDbType.VarChar, 40) { Value = entidad });
        cmd.Parameters.Add(new SqlParameter("@Modo", SqlDbType.VarChar, 20) { Value = modo });
        cmd.Parameters.Add(new SqlParameter("@Propietario", SqlDbType.NVarChar, 200) { Value = propietario });
        cmd.Parameters.Add(new SqlParameter("@DuracionCandadoSeg", SqlDbType.Int) { Value = duracionCandadoSeg });
        var salida = cmd.Parameters.Add(new SqlParameter("@EjecucionId", SqlDbType.BigInt) { Direction = ParameterDirection.Output });
        try
        {
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (SqlException ex) when (ex.Number == ErrorCandadoOcupado)
        {
            throw new CandadoOcupadoException(fuente, ex);
        }
        return (long)salida.Value;
    }

    public async Task<bool> RenovarCandadoAsync(string fuente, string propietario, int duracionCandadoSeg, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Candado_Renovar");
        cmd.Parameters.Add(new SqlParameter("@Fuente", SqlDbType.VarChar, 50) { Value = fuente });
        cmd.Parameters.Add(new SqlParameter("@Propietario", SqlDbType.NVarChar, 200) { Value = propietario });
        cmd.Parameters.Add(new SqlParameter("@DuracionCandadoSeg", SqlDbType.Int) { Value = duracionCandadoSeg });
        var vigente = cmd.Parameters.Add(new SqlParameter("@Vigente", SqlDbType.Bit) { Direction = ParameterDirection.Output });
        await cmd.ExecuteNonQueryAsync(ct);
        return (bool)vigente.Value;
    }

    public async Task LiberarCandadoAsync(string fuente, string propietario, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Candado_Liberar");
        cmd.Parameters.Add(new SqlParameter("@Fuente", SqlDbType.VarChar, 50) { Value = fuente });
        cmd.Parameters.Add(new SqlParameter("@Propietario", SqlDbType.NVarChar, 200) { Value = propietario });
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<MarcaAgua> ObtenerMarcaAguaAsync(string fuente, string entidad, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.MarcaAgua_Obtener");
        cmd.Parameters.Add(new SqlParameter("@Fuente", SqlDbType.VarChar, 50) { Value = fuente });
        cmd.Parameters.Add(new SqlParameter("@Entidad", SqlDbType.VarChar, 40) { Value = entidad });
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) throw new InvalidOperationException($"La fuente '{fuente}' no existe en la base.");
        return new MarcaAgua(r.IsDBNull(2) ? null : r.GetDateTimeOffset(2), r.GetDateTimeOffset(3), r.GetBoolean(4));
    }

    public async Task<int> CargarDocumentosAsync(long ejecucionId, IReadOnlyList<DocumentoJira> documentos, CancellationToken ct)
    {
        if (documentos.Count == 0) return 0;
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Documento_Cargar");
        cmd.Parameters.Add(new SqlParameter("@EjecucionId", SqlDbType.BigInt) { Value = ejecucionId });
        cmd.Parameters.Add(new SqlParameter("@Documentos", SqlDbType.Structured) { TypeName = "sync.DocumentoTipo", Value = Registros(documentos) });
        var cambiados = cmd.Parameters.Add(new SqlParameter("@Cambiados", SqlDbType.Int) { Direction = ParameterDirection.Output });
        await cmd.ExecuteNonQueryAsync(ct);
        return cambiados.Value is int n ? n : 0;
    }

    public async Task<int> ProcesarPendientesAsync(int fuenteId, long ejecucionId, string entidad, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Procesar_Pendientes");
        cmd.Parameters.Add(new SqlParameter("@FuenteId", SqlDbType.Int) { Value = fuenteId });
        cmd.Parameters.Add(new SqlParameter("@EjecucionId", SqlDbType.BigInt) { Value = ejecucionId });
        cmd.Parameters.Add(new SqlParameter("@Entidad", SqlDbType.VarChar, 40) { Value = entidad });
        var procesados = cmd.Parameters.Add(new SqlParameter("@Procesados", SqlDbType.Int) { Direction = ParameterDirection.Output });
        await cmd.ExecuteNonQueryAsync(ct);
        return procesados.Value is int n ? n : 0;
    }

    public async Task FinalizarEjecucionAsync(long ejecucionId, string estado, string? mensaje, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Ejecucion_Finalizar");
        cmd.Parameters.Add(new SqlParameter("@EjecucionId", SqlDbType.BigInt) { Value = ejecucionId });
        cmd.Parameters.Add(new SqlParameter("@Estado", SqlDbType.VarChar, 15) { Value = estado });
        cmd.Parameters.Add(new SqlParameter("@Mensaje", SqlDbType.NVarChar, 2000) { Value = (object?)Recortar(mensaje, 2000) ?? DBNull.Value });
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<SolicitudSync?> TomarSolicitudAsync(string propietario, IReadOnlyCollection<string> fuentes, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Solicitud_Tomar");
        cmd.Parameters.Add(new SqlParameter("@Propietario", SqlDbType.NVarChar, 200) { Value = propietario });
        cmd.Parameters.Add(new SqlParameter("@Fuentes", SqlDbType.NVarChar, 1000) { Value = string.Join(",", fuentes) });
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) return null;
        return new SolicitudSync(r.GetInt64(0), r.IsDBNull(1) ? null : r.GetString(1), r.IsDBNull(2) ? null : r.GetString(2),
                                 r.GetString(3), r.IsDBNull(4) ? null : r.GetString(4));
    }

    public async Task TerminarSolicitudAsync(long solicitudId, string estado, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Solicitud_Terminar");
        cmd.Parameters.Add(new SqlParameter("@SolicitudId", SqlDbType.BigInt) { Value = solicitudId });
        cmd.Parameters.Add(new SqlParameter("@Estado", SqlDbType.VarChar, 15) { Value = estado });
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<int> ConciliarIdsAsync(long ejecucionId, string proyectoId, IReadOnlyCollection<string> ids, CancellationToken ct)
    {
        await using var cn = await AbrirAsync(ct);
        await using var cmd = Comando(cn, "sync.Issue_ConciliarIds");
        cmd.Parameters.Add(new SqlParameter("@EjecucionId", SqlDbType.BigInt) { Value = ejecucionId });
        cmd.Parameters.Add(new SqlParameter("@ProyectoId", SqlDbType.VarChar, 30) { Value = proyectoId });
        // Un TVP vacío se envía como null (SqlClient no acepta una enumeración sin filas).
        cmd.Parameters.Add(new SqlParameter("@Ids", SqlDbType.Structured) { TypeName = "sync.IdTipo", Value = ids.Count == 0 ? null : RegistrosId(ids) });
        var resultado = await cmd.ExecuteScalarAsync(ct);
        return resultado is int n ? n : 0;
    }

    private async Task<SqlConnection> AbrirAsync(CancellationToken ct)
    {
        var cn = new SqlConnection(cadenaConexion);
        await cn.OpenAsync(ct);
        return cn;
    }

    private SqlCommand Comando(SqlConnection cn, string procedimiento) =>
        new(procedimiento, cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = timeoutSegundos };

    private static IEnumerable<SqlDataRecord> Registros(IEnumerable<DocumentoJira> documentos)
    {
        // Un mismo id puede repetirse en páginas solapadas: gana el último (la PK del TVP no admite duplicados).
        foreach (var d in documentos.GroupBy(x => x.IdExterno).Select(g => g.Last()))
        {
            var r = new SqlDataRecord(MetaDocumento);
            r.SetString(0, d.IdExterno);
            if (d.Actualizado is { } a) r.SetDateTimeOffset(1, a); else r.SetDBNull(1);
            r.SetString(2, d.Json);
            yield return r;
        }
    }

    private static IEnumerable<SqlDataRecord> RegistrosId(IEnumerable<string> ids)
    {
        foreach (var id in ids.Distinct())
        {
            var r = new SqlDataRecord(MetaId);
            r.SetString(0, id);
            yield return r;
        }
    }

    private static string? Recortar(string? s, int max) => s is null || s.Length <= max ? s : s[..max];
}
