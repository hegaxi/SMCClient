/* Alarga el candado mientras una carga larga sigue avanzando. Devuelve 0 si ya no es del propietario
   (expiró y otro worker lo tomó): en ese caso el worker debe detenerse. */
CREATE OR ALTER PROCEDURE sync.Candado_Renovar
    @Fuente             varchar(50),
    @Propietario        nvarchar(200),
    @DuracionCandadoSeg int = 900,
    @Vigente            bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE c SET ExpiraEn = DATEADD(SECOND, @DuracionCandadoSeg, SYSDATETIMEOFFSET())
    FROM sync.Candado c JOIN cfg.Fuente f ON f.FuenteId = c.FuenteId
    WHERE f.Codigo = @Fuente AND c.Propietario = @Propietario;
    SET @Vigente = CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END;
END;
GO
