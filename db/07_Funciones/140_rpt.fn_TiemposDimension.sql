/* Una agrupación de api.Tiempos_Invertidos para un worklog: Llave (agrupa), Clave (de issue, si la agrupación es un
   issue: abre el detalle), Texto (lo que se muestra) y Orden (las claves de issue por número, "(Sin …)" al final).
   @Dim: persona | proyecto | epica | tarea | issue | tipo | estado. NULL = no hay agrupación en ese nivel. */
CREATE OR ALTER FUNCTION rpt.fn_TiemposDimension (
    @Dim varchar(10), @Persona nvarchar(255), @ProyectoClave varchar(50), @ProyectoNombre nvarchar(255),
    @EpicaClave varchar(50), @EpicaResumen nvarchar(1000), @TareaClave varchar(50), @TareaResumen nvarchar(1000),
    @Clave varchar(50), @Resumen nvarchar(1000), @TipoIssue nvarchar(255), @Estado nvarchar(255))
RETURNS TABLE
AS
RETURN
    SELECT x.Llave, x.Clave, x.Texto,
           CAST(CASE WHEN x.Llave = N'~' THEN N'~~~~'
                     WHEN x.Clave IS NOT NULL
                         THEN CONCAT(LEFT(x.Clave + SPACE(20), CHARINDEX('-', x.Clave + '-')), RIGHT(REPLICATE('0', 9) + SUBSTRING(x.Clave, CHARINDEX('-', x.Clave) + 1, 20), 9))
                     ELSE LOWER(x.Texto) END AS nvarchar(400)) AS Orden
    FROM (SELECT
            CAST(CASE @Dim WHEN 'persona'  THEN ISNULL(@Persona, N'~')
                           WHEN 'proyecto' THEN @ProyectoClave
                           WHEN 'epica'    THEN ISNULL(@EpicaClave, N'~')
                           WHEN 'tarea'    THEN @TareaClave
                           WHEN 'issue'    THEN @Clave
                           WHEN 'tipo'     THEN ISNULL(@TipoIssue, N'~')
                           WHEN 'estado'   THEN ISNULL(NULLIF(@Estado, N''), N'~') END AS nvarchar(300)) AS Llave,
            CAST(CASE @Dim WHEN 'epica' THEN @EpicaClave WHEN 'tarea' THEN @TareaClave WHEN 'issue' THEN @Clave END AS varchar(50)) AS Clave,
            CAST(CASE @Dim WHEN 'persona'  THEN ISNULL(@Persona, N'(Sin responsable)')
                           WHEN 'proyecto' THEN CONCAT(@ProyectoClave, N' · ', @ProyectoNombre)
                           WHEN 'epica'    THEN ISNULL(@EpicaResumen, N'(Sin épica)')
                           WHEN 'tarea'    THEN @TareaResumen
                           WHEN 'issue'    THEN @Resumen
                           WHEN 'tipo'     THEN ISNULL(@TipoIssue, N'(Sin tipo)')
                           WHEN 'estado'   THEN ISNULL(NULLIF(@Estado, N''), N'(Sin estado)') END AS nvarchar(400)) AS Texto
          WHERE @Dim IS NOT NULL) x;
GO
