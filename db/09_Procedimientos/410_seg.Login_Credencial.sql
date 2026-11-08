/* Datos para que la API verifique una contraseña (hash, sal, iteraciones). No devuelve nada si el usuario no
   existe o no tiene contraseña; la API responde igual en todos los casos para no revelar qué usuarios existen. */
CREATE OR ALTER PROCEDURE seg.Login_Credencial
    @Login nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ContrasenaHash, ContrasenaSal, ContrasenaIteraciones
    FROM seg.Usuario
    WHERE Login = @Login AND ContrasenaHash IS NOT NULL;
END;
GO
