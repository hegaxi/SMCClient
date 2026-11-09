/* Ejecuta una consulta personalizada con los criterios y columnas que definió el administrador (el usuario solo elige
   página y orden). Si el usuario es externo (cliente), se agrega un criterio que la limita a los tickets de SUS
   organizaciones de mesa de ayuda; sin organización asignada no ve tickets. La seguridad de la consulta (lista blanca,
   valores leídos del JSON) es la de api.Issues_Consultar. */
CREATE OR ALTER PROCEDURE api.ConsultaPersonalizada_Ejecutar
    @ConsultaId    int,
    @OrdenarPor    varchar(60) = NULL,
    @Descendente   bit = NULL,
    @Pagina        int = 1,
    @TamanoPagina  int = 50,
    @UsuarioActual nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @u int = (SELECT UsuarioId FROM seg.Usuario WHERE Login = @UsuarioActual AND Activo = 1);
    IF NOT EXISTS (SELECT 1 FROM dash.Consulta WHERE ConsultaId = @ConsultaId) THROW 50404, 'La consulta no existe.', 1;
    IF @u IS NULL OR (seg.fn_EsAdministrador(@u) = 0 AND NOT EXISTS (
        SELECT 1 FROM dash.ConsultaAcceso x WHERE x.ConsultaId = @ConsultaId
          AND ((x.Tipo = 'U' AND x.Id = @u) OR (x.Tipo = 'R' AND x.Id IN (SELECT RolId FROM seg.UsuarioRol WHERE UsuarioId = @u)))))
        THROW 50403, 'No tiene acceso a esta consulta.', 1;

    DECLARE @crit nvarchar(max), @cols nvarchar(2000), @ord varchar(60), @desc bit;
    SELECT @crit = Criterios, @cols = Columnas, @ord = OrdenarPor, @desc = Descendente FROM dash.Consulta WHERE ConsultaId = @ConsultaId;

    IF seg.fn_EsExterno(@u) = 1
    BEGIN
        -- Valores como arreglo JSON; sin organización, un valor que no coincide con ninguna.
        DECLARE @orgs nvarchar(max) = (SELECT N'[' + STRING_AGG(N'"' + STRING_ESCAPE(Organizacion, 'json') + N'"', N',') + N']'
                                       FROM seg.UsuarioOrganizacion WHERE UsuarioId = @u);
        SET @orgs = ISNULL(@orgs, N'["' + CAST(NEWID() AS nvarchar(36)) + N'"]');
        SET @crit = JSON_MODIFY(@crit, 'append $', JSON_QUERY(N'{"campo":"organizacion","operador":"en","valores":' + @orgs + N'}'));
    END;

    SET @OrdenarPor = COALESCE(NULLIF(@OrdenarPor, ''), @ord);
    SET @Descendente = COALESCE(@Descendente, @desc, 1);
    EXEC api.Issues_Consultar @Criterios = @crit, @Columnas = @cols, @OrdenarPor = @OrdenarPor, @Descendente = @Descendente,
         @Pagina = @Pagina, @TamanoPagina = @TamanoPagina;
END;
GO
