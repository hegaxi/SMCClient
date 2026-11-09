/* El worker toma la solicitud pendiente más antigua de LAS FUENTES QUE ATIENDE (o de todas, si la
   solicitud no indica fuente). READPAST: varios workers no toman la misma. Filtrar por fuente evita que
   una solicitud de otra instancia de Jira bloquee la cola de este worker. */
CREATE OR ALTER PROCEDURE sync.Solicitud_Tomar
    @Propietario nvarchar(200),
    @Fuentes     nvarchar(1000) = NULL     -- códigos separados por coma; NULL = cualquiera
AS
BEGIN
    SET NOCOUNT ON;
    WITH s AS (
        SELECT TOP (1) * FROM sync.Solicitud WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE Estado = 'pendiente'
          AND (@Fuentes IS NULL OR FuenteId IS NULL
               OR FuenteId IN (SELECT f.FuenteId FROM cfg.Fuente f JOIN STRING_SPLIT(@Fuentes, ',') x ON f.Codigo = LTRIM(RTRIM(x.value))))
        ORDER BY Fecha
    )
    UPDATE s SET Estado = 'tomada', TomadaEn = SYSDATETIMEOFFSET()
    OUTPUT inserted.SolicitudId, f.Codigo AS Fuente, inserted.Entidad, inserted.Modo, inserted.Parametros
    FROM s LEFT JOIN cfg.Fuente f ON f.FuenteId = s.FuenteId;
END;
GO
