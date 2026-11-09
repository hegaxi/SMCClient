/* Búsqueda paginada de issues/tickets. Contrato FIJO de columnas: agregar o quitar campos en Jira
   no cambia este resultado (los campos extra se consultan en api.Issue_Detalle). */
CREATE OR ALTER PROCEDURE api.Issues_Buscar
    @Proyecto       varchar(50)  = NULL,
    @TipoProyecto   varchar(30)  = NULL,
    @Categoria      varchar(20)  = NULL,   -- new | indeterminate | done
    @ResponsableId  varchar(128) = NULL,
    @Texto          nvarchar(200) = NULL,
    @CreadoDesde    date = NULL,
    @CreadoHasta    date = NULL,
    @Pagina         int = 1,
    @TamanoPagina   int = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina NOT BETWEEN 1 AND 500 SET @TamanoPagina = 50;

    SELECT i.Clave, i.ProyectoClave, i.TipoProyecto, i.TipoIssue, i.TipoSolicitud, i.Resumen, i.Estado, i.CategoriaEstado,
           i.Prioridad, i.Responsable, i.Informante, i.StoryPoints,
           CAST(i.TiempoInvertidoSeg / 3600.0 AS decimal(12,2)) AS HorasInvertidas,
           CAST(i.EstimacionOriginalSeg / 3600.0 AS decimal(12,2)) AS HorasEstimadas,
           i.Creado, i.Actualizado, i.Resuelto, i.Vencimiento,
           COUNT(*) OVER () AS TotalFilas
    FROM rpt.vIssue i
    WHERE (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto)
      AND (@TipoProyecto IS NULL OR i.TipoProyecto = @TipoProyecto)
      AND (@Categoria IS NULL OR i.CategoriaEstado = @Categoria)
      AND (@ResponsableId IS NULL OR i.ResponsableId = @ResponsableId)
      AND (@Texto IS NULL OR i.Resumen LIKE N'%' + @Texto + N'%' OR i.Clave = @Texto)
      AND (@CreadoDesde IS NULL OR i.Creado >= CAST(@CreadoDesde AS datetimeoffset(3)))
      AND (@CreadoHasta IS NULL OR i.Creado < DATEADD(DAY, 1, CAST(@CreadoHasta AS datetimeoffset(3))))
    ORDER BY i.Actualizado DESC, i.IssueSk DESC
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY
    OPTION (RECOMPILE);
END;
GO
