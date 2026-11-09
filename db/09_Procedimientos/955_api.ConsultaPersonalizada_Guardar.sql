/* Publica (o modifica) una consulta personalizada a partir de una búsqueda avanzada y la comparte con usuarios o roles:
   @CompartirCon = "ana, cliente1, rol:Cliente". Solo quien tiene la opción "Publicar consulta personalizada". Los criterios, columnas y orden se validan con las
   mismas reglas de api.Issues_Consultar. */
CREATE OR ALTER PROCEDURE api.ConsultaPersonalizada_Guardar
    @ConsultaId    int = NULL,
    @Nombre        nvarchar(150),
    @Descripcion   nvarchar(500) = NULL,
    @Criterios     nvarchar(max) = N'[]',
    @Columnas      nvarchar(2000) = NULL,
    @OrdenarPor    varchar(60) = NULL,
    @Descendente   bit = 1,
    @CompartirCon  nvarchar(1000) = NULL,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF NOT EXISTS (SELECT 1 FROM seg.fn_ProcedimientosPermitidos(@u) WHERE Procedimiento = N'ConsultaPersonalizada_Guardar')
        THROW 50403, 'No tiene permiso para publicar consultas personalizadas.', 1;
    SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, N'')));
    SET @Criterios = ISNULL(NULLIF(LTRIM(RTRIM(@Criterios)), N''), N'[]');
    SET @Columnas = NULLIF(REPLACE(LTRIM(RTRIM(@Columnas)), N' ', N''), N'');
    SET @OrdenarPor = NULLIF(@OrdenarPor, '');
    IF @Nombre = N'' THROW 50400, 'El nombre es obligatorio.', 1;
    IF @ConsultaId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dash.Consulta WHERE ConsultaId = @ConsultaId) THROW 50404, 'La consulta no existe.', 1;
    IF EXISTS (SELECT 1 FROM dash.Consulta WHERE Nombre = @Nombre AND ConsultaId <> ISNULL(@ConsultaId, -1))
        THROW 50409, 'Ya existe una consulta personalizada con ese nombre.', 1;

    -- Mismas validaciones que la búsqueda: criterios (lanza 50400 con el detalle), columnas y orden.
    DECLARE @where nvarchar(max), @hoy date = CAST(SYSDATETIMEOFFSET() AS date), @msg nvarchar(1000);
    EXEC rpt.Buscador_Condiciones @Criterios = @Criterios, @Hoy = @hoy, @Where = @where OUTPUT;
    SET @msg = (SELECT STRING_AGG(CAST(c.value AS nvarchar(100)), N', ') FROM STRING_SPLIT(ISNULL(@Columnas, N''), ',') c
                WHERE c.value <> N'' AND NOT EXISTS (SELECT 1 FROM rpt.fn_CamposBuscador() f WHERE f.Clave = c.value AND f.EsColumna = 1));
    IF @msg IS NOT NULL BEGIN SET @msg = N'Columnas desconocidas: ' + @msg + N'.'; THROW 50400, @msg, 1; END;
    IF @OrdenarPor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM rpt.fn_CamposBuscador() WHERE Clave = @OrdenarPor AND Expresion IS NOT NULL)
        THROW 50400, 'Solo se puede ordenar por campos de un solo valor.', 1;

    DECLARE @destinos TABLE (Texto nvarchar(200), Tipo char(1), Id int);
    INSERT @destinos (Texto, Tipo, Id)
    SELECT x.Texto,
           CASE WHEN x.Texto LIKE N'rol:%' THEN 'R' ELSE 'U' END,
           CASE WHEN x.Texto LIKE N'rol:%' THEN (SELECT RolId FROM seg.Rol WHERE Nombre = LTRIM(SUBSTRING(x.Texto, 5, 200)))
                ELSE (SELECT UsuarioId FROM seg.Usuario WHERE Login = x.Texto) END
    FROM (SELECT DISTINCT LTRIM(RTRIM(value)) AS Texto FROM STRING_SPLIT(ISNULL(@CompartirCon, N''), ',') WHERE LTRIM(RTRIM(value)) <> N'') x;
    SET @msg = (SELECT STRING_AGG(Texto, N', ') FROM @destinos WHERE Id IS NULL);
    IF @msg IS NOT NULL BEGIN SET @msg = N'No existen: ' + @msg + N'. Use el nombre de usuario o rol:NombreDelRol.'; THROW 50400, @msg, 1; END;

    DECLARE @antes nvarchar(max) = (SELECT Nombre, Criterios, Columnas FROM dash.Consulta WHERE ConsultaId = @ConsultaId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRAN;
    IF @ConsultaId IS NULL
    BEGIN
        INSERT dash.Consulta (Nombre, Descripcion, Criterios, Columnas, OrdenarPor, Descendente, PropietarioId)
        VALUES (@Nombre, NULLIF(LTRIM(RTRIM(@Descripcion)), N''), @Criterios, @Columnas, @OrdenarPor, ISNULL(@Descendente, 1), @u);
        SET @ConsultaId = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dash.Consulta SET Nombre = @Nombre, Descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), N''), Criterios = @Criterios,
            Columnas = @Columnas, OrdenarPor = @OrdenarPor, Descendente = ISNULL(@Descendente, 1), FechaCambio = SYSDATETIMEOFFSET()
        WHERE ConsultaId = @ConsultaId;
    DELETE dash.ConsultaAcceso WHERE ConsultaId = @ConsultaId;
    INSERT dash.ConsultaAcceso (ConsultaId, Tipo, Id) SELECT DISTINCT @ConsultaId, Tipo, Id FROM @destinos;
    DECLARE @despues nvarchar(max) = (SELECT @Nombre AS Nombre, @Criterios AS Criterios, @Columnas AS Columnas, @CompartirCon AS CompartirCon FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC seg.Auditoria_Registrar @Usuario = @UsuarioActual, @Accion = 'consulta.guardar', @Objeto = @Nombre, @Antes = @antes, @Despues = @despues;
    COMMIT;

    SELECT @ConsultaId AS ConsultaId;
END;
GO
