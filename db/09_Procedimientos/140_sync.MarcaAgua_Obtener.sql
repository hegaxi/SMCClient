/* Desde qué fecha debe pedir el worker los cambios: marca de agua menos el traslape
   (cubre relojes desfasados y registros guardados durante la consulta anterior).
   Sin marca de agua: carga inicial de cfg.Parametro 'DiasCargaInicial'. */
CREATE OR ALTER PROCEDURE sync.MarcaAgua_Obtener
    @Fuente  varchar(50),
    @Entidad varchar(40)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @traslape int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'TraslapeMin') AS int), 5);
    DECLARE @dias int = ISNULL(TRY_CAST((SELECT Valor FROM cfg.Parametro WHERE Clave = 'DiasCargaInicial') AS int), 365);

    SELECT f.FuenteId, @Entidad AS Entidad, m.Valor AS MarcaAgua,
           CASE WHEN m.Valor IS NULL THEN DATEADD(DAY, -@dias, SYSDATETIMEOFFSET())
                ELSE DATEADD(MINUTE, -@traslape, m.Valor) END AS Desde,
           CAST(CASE WHEN m.Valor IS NULL THEN 1 ELSE 0 END AS bit) AS EsCargaInicial
    FROM cfg.Fuente f
    LEFT JOIN sync.MarcaAgua m ON m.FuenteId = f.FuenteId AND m.Entidad = @Entidad
    WHERE f.Codigo = @Fuente;
END;
GO
