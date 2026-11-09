/* Aplica las reglas de cfg.RolCampo al catálogo actual y actualiza cfg.MapeoCampo.
   Prioridad de la regla: campo del sistema > tipo custom > nombre. Si una regla encuentra varios
   campos, se elige el de ID más bajo y se avisa (rol.ambiguo). Los mapeos 'manual' no se tocan.
   Si algún mapeo cambia, se marcan los issues para reprocesarse desde raw.Documento. */
CREATE OR ALTER PROCEDURE sync.ResolverMapeos
    @FuenteId    int,
    @EjecucionId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @msg nvarchar(1000), @datos nvarchar(max);

    WITH cand AS (
        SELECT r.Rol, c.CampoId,
               CASE WHEN c.CampoId = r.ReglaCampoSistema THEN 1
                    WHEN c.TipoCustom = r.ReglaTipoCustom THEN 2
                    ELSE 3 END AS Prioridad
        FROM cfg.RolCampo r
        JOIN meta.CampoJira c ON c.FuenteId = @FuenteId AND c.Activo = 1
        WHERE c.CampoId = r.ReglaCampoSistema
           OR (r.ReglaTipoCustom IS NOT NULL AND c.TipoCustom = r.ReglaTipoCustom)
           OR (r.ReglaNombre IS NOT NULL AND c.Nombre IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(r.ReglaNombre, '|')))
    ), orden AS (
        SELECT Rol, CampoId, Prioridad,
               ROW_NUMBER() OVER (PARTITION BY Rol ORDER BY Prioridad, LEN(CampoId), CampoId) AS rn,
               COUNT(*) OVER (PARTITION BY Rol, Prioridad) AS Empates
        FROM cand
    )
    SELECT r.Rol, r.Obligatorio,
           -- Un campo del sistema siempre existe en Jira: si el catálogo aún no llegó se usa su id.
           COALESCE(o.CampoId, r.ReglaCampoSistema) AS CampoId,
           ISNULL(o.Empates, 0) AS Empates
    INTO #res
    FROM cfg.RolCampo r
    LEFT JOIN orden o ON o.Rol = r.Rol AND o.rn = 1;

    SELECT r.Rol, m.CampoId AS Anterior, r.CampoId AS Nuevo, CAST(CASE WHEN m.Rol IS NULL THEN 0 ELSE 1 END AS bit) AS Existia
    INTO #cambios
    FROM #res r
    LEFT JOIN cfg.MapeoCampo m ON m.FuenteId = @FuenteId AND m.Rol = r.Rol
    WHERE ISNULL(m.Origen, 'auto') = 'auto'
      AND (m.Rol IS NULL OR ISNULL(m.CampoId, '') <> ISNULL(r.CampoId, ''));

    BEGIN TRAN;
    MERGE cfg.MapeoCampo AS t
    USING (SELECT Rol, Nuevo FROM #cambios) AS s ON t.FuenteId = @FuenteId AND t.Rol = s.Rol
    WHEN MATCHED THEN UPDATE SET CampoId = s.Nuevo, FechaResolucion = SYSDATETIMEOFFSET()
    WHEN NOT MATCHED THEN INSERT (FuenteId, Rol, CampoId, Origen) VALUES (@FuenteId, s.Rol, s.Nuevo, 'auto');

    -- Si cambió el campo de algún rol que ya tenía valor, se reprocesan los issues desde raw.
    DECLARE @reproceso int = 0;
    IF EXISTS (SELECT 1 FROM #cambios WHERE Existia = 1)
    BEGIN
        UPDATE raw.Documento SET Procesado = 0, Intentos = 0, ErrorProceso = NULL
        WHERE FuenteId = @FuenteId AND Entidad = 'issue' AND Procesado = 1;
        SET @reproceso = @@ROWCOUNT;
    END;
    COMMIT;

    IF EXISTS (SELECT 1 FROM #cambios WHERE Existia = 1)
    BEGIN
        SET @datos = (SELECT Rol, Anterior, Nuevo FROM #cambios WHERE Existia = 1 FOR JSON PATH, INCLUDE_NULL_VALUES);
        SET @msg = CONCAT(N'Cambió el campo de Jira asociado a uno o más roles. Se reprocesarán ', @reproceso, N' issue(s) desde los datos guardados.');
        EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'rol.cambio', @msg, @datos;
    END;

    -- Avisos de roles sin campo (solo si ya hay catálogo) y de reglas ambiguas.
    IF EXISTS (SELECT 1 FROM meta.CampoJira WHERE FuenteId = @FuenteId)
    BEGIN
        DECLARE @rol varchar(50);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT r.Rol FROM #res r
            LEFT JOIN cfg.MapeoCampo m ON m.FuenteId = @FuenteId AND m.Rol = r.Rol
            WHERE r.Obligatorio = 1 AND m.CampoId IS NULL;
        OPEN c; FETCH c INTO @rol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @msg = CONCAT(N'El rol obligatorio "', @rol, N'" no tiene campo en Jira. Asígnelo manualmente (api.Mapeo_Establecer).');
            SET @datos = CONCAT(N'{"rol":"', @rol, N'"}');
            EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'rol.sin_campo', @msg, @datos;
            FETCH c INTO @rol;
        END;
        CLOSE c; DEALLOCATE c;

        DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR SELECT Rol FROM #res WHERE Empates > 1;
        OPEN c2; FETCH c2 INTO @rol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @datos = (SELECT r.Rol AS rol, r.CampoId AS elegido FROM #res r WHERE r.Rol = @rol FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            SET @msg = CONCAT(N'La regla del rol "', @rol, N'" coincide con varios campos; se eligió el de ID más bajo. Confirme con api.Mapeo_Establecer.');
            EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'rol.ambiguo', @msg, @datos;
            FETCH c2 INTO @rol;
        END;
        CLOSE c2; DEALLOCATE c2;

        DECLARE c3 CURSOR LOCAL FAST_FORWARD FOR
            SELECT m.Rol FROM cfg.MapeoCampo m
            JOIN meta.CampoJira cj ON cj.FuenteId = m.FuenteId AND cj.CampoId = m.CampoId
            WHERE m.FuenteId = @FuenteId AND m.Origen = 'manual' AND cj.Activo = 0;
        OPEN c3; FETCH c3 INTO @rol;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @msg = CONCAT(N'El campo asignado manualmente al rol "', @rol, N'" ya no existe en Jira.');
            SET @datos = CONCAT(N'{"rol":"', @rol, N'"}');
            EXEC sync.Evento_Registrar @FuenteId, @EjecucionId, 'advertencia', 'rol.manual_inactivo', @msg, @datos;
            FETCH c3 INTO @rol;
        END;
        CLOSE c3; DEALLOCATE c3;
    END;
END;
GO
