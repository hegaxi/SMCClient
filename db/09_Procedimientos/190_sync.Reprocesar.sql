/* Vuelve a integrar desde raw.Documento (sin llamar a Jira). Útil después de cambiar un mapeo
   o de corregir un procedimiento Procesar_*. */
CREATE OR ALTER PROCEDURE sync.Reprocesar
    @Fuente  varchar(50),
    @Entidad varchar(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d SET Procesado = 0, Intentos = 0, ErrorProceso = NULL
    FROM raw.Documento d JOIN cfg.Fuente f ON f.FuenteId = d.FuenteId
    WHERE f.Codigo = @Fuente AND (@Entidad IS NULL OR d.Entidad = @Entidad);
    SELECT @@ROWCOUNT AS DocumentosMarcados;
END;
GO
