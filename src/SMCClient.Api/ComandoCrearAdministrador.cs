using System.Data;
using System.Text;
using Microsoft.Data.SqlClient;
using SMCClient.Api.Seguridad;

namespace SMCClient.Api;

/// <summary>
/// dotnet SMCClient.Api.dll crear-administrador --usuario admin --nombre "Administrador" [--cadena "..."]
/// Crea (o recupera) un administrador. Pide la contraseña en la consola (o la lee de la entrada estándar)
/// y solo envía su hash. Usa ConnectionStrings:SMCClientAdmin (o --cadena): una cuenta con permisos de
/// administración de la base, porque seg.Instalacion_CrearAdministrador no está permitido para la API.
/// </summary>
public static class ComandoCrearAdministrador
{
    public static async Task<int> EjecutarAsync(string[] args, IConfiguration configuracion)
    {
        string? Opcion(string nombre) { var i = Array.IndexOf(args, nombre); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }

        var usuario = Opcion("--usuario");
        var nombre = Opcion("--nombre") ?? usuario;
        var cadena = Opcion("--cadena") ?? configuracion.GetConnectionString("SMCClientAdmin") ?? configuracion.GetConnectionString("SMCClient");
        if (string.IsNullOrWhiteSpace(usuario) || string.IsNullOrWhiteSpace(cadena))
        {
            Console.Error.WriteLine("Uso: crear-administrador --usuario <usuario> [--nombre <nombre>] [--cadena <conexión de administrador>]");
            return 2;
        }

        var contrasena = LeerContrasena("Contraseña: ");
        if (LeerContrasena("Repita la contraseña: ") != contrasena)
        {
            Console.Error.WriteLine("Las contraseñas no coinciden.");
            return 1;
        }

        var hash = Contrasenas.Calcular(contrasena);
        try
        {
            await using var cn = new SqlConnection(cadena);
            await cn.OpenAsync();
            await using var cmd = new SqlCommand("seg.Instalacion_CrearAdministrador", cn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.Add(new SqlParameter("@Login", SqlDbType.NVarChar, 100) { Value = usuario.Trim() });
            cmd.Parameters.Add(new SqlParameter("@Nombre", SqlDbType.NVarChar, 200) { Value = nombre!.Trim() });
            cmd.Parameters.Add(new SqlParameter("@Hash", SqlDbType.VarBinary, 64) { Value = hash.Hash });
            cmd.Parameters.Add(new SqlParameter("@Sal", SqlDbType.VarBinary, 32) { Value = hash.Sal });
            cmd.Parameters.Add(new SqlParameter("@Iteraciones", SqlDbType.Int) { Value = hash.Iteraciones });
            cmd.Parameters.Add(new SqlParameter("@Longitud", SqlDbType.Int) { Value = contrasena.Length });
            await cmd.ExecuteNonQueryAsync();
        }
        catch (SqlException ex)
        {
            Console.Error.WriteLine($"No se pudo crear el administrador: {ex.Message}");
            return 1;
        }
        Console.WriteLine($"Administrador '{usuario}' listo. Ya puede iniciar sesión.");
        return 0;
    }

    private static string LeerContrasena(string mensaje)
    {
        if (Console.IsInputRedirected) return Console.ReadLine() ?? "";   // automatización: una línea por contraseña
        Console.Write(mensaje);
        var sb = new StringBuilder();
        while (true)
        {
            var k = Console.ReadKey(intercept: true);
            if (k.Key == ConsoleKey.Enter) break;
            if (k.Key == ConsoleKey.Backspace) { if (sb.Length > 0) sb.Length--; continue; }
            if (!char.IsControl(k.KeyChar)) sb.Append(k.KeyChar);
        }
        Console.WriteLine();
        return sb.ToString();
    }
}
