using System.Security.Cryptography;
using System.Text;

namespace SMCClient.Api.Seguridad;

/// <summary>Hash de contraseña calculado en .NET: la contraseña en claro nunca llega a SQL Server.</summary>
public sealed record HashContrasena(byte[] Hash, byte[] Sal, int Iteraciones);

/// <summary>
/// PBKDF2-HMAC-SHA256, 600 000 iteraciones (recomendación OWASP), sal aleatoria de 16 bytes, hash de 32 bytes.
/// Las reglas (longitud mínima, quién puede cambiar qué) las decide la base de datos.
/// </summary>
public static class Contrasenas
{
    public const int Iteraciones = 600_000;
    private const int BytesSal = 16;
    private const int BytesHash = 32;

    // Para no revelar si un usuario existe, se calcula un hash aunque el usuario no tenga credencial.
    private static readonly HashContrasena Ficticia = Calcular("contraseña-ficticia-para-tiempo-constante");

    public static HashContrasena Calcular(string contrasena)
    {
        var sal = RandomNumberGenerator.GetBytes(BytesSal);
        return new HashContrasena(Derivar(contrasena, sal, Iteraciones), sal, Iteraciones);
    }

    /// <summary>Compara en tiempo constante. Con credencial nula hace el mismo trabajo y devuelve false.</summary>
    public static bool Verificar(string contrasena, HashContrasena? guardada)
    {
        var c = guardada ?? Ficticia;
        var calculado = Derivar(contrasena, c.Sal, c.Iteraciones);
        return guardada is not null && CryptographicOperations.FixedTimeEquals(calculado, c.Hash);
    }

    private static byte[] Derivar(string contrasena, byte[] sal, int iteraciones) =>
        Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(contrasena), sal, iteraciones, HashAlgorithmName.SHA256, BytesHash);
}
