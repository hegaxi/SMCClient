/* Cumplimiento de SLA por proyecto y SLA en el periodo, medido como lo hace JSM:
   - se miden los ciclos TERMINADOS en el periodo (por su fecha de fin) y los que siguen en curso pero ya VENCIERON en
     el periodo; % = cumplidos / (cumplidos + incumplidos). Los ciclos en curso sin vencer no cuentan (antes contaban
     como cumplidos e inflaban el %).
   - el periodo es en la hora local del servidor (antes se tomaba en UTC y movía 6 h los tickets del borde del día).
   - EnCursoAhora: ciclos abiertos sin vencer hoy (contexto). EnCursoEnTicketCerrado: ciclos que JSM no detuvo al cerrar
     el ticket (falta la condición de paro en la configuración del SLA).
   Segundo resultado (@TicketsSinSla = 1): tickets de mesa de ayuda creados en el periodo sin ningún ciclo de SLA (el SLA
   nunca empezó: quedan fuera de la medición). */
CREATE OR ALTER PROCEDURE api.Sla_Resumen
    @Desde         date,
    @Hasta         date,
    @Proyecto      varchar(50) = NULL,
    @TicketsSinSla bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @tz int = DATEPART(TZOFFSET, SYSDATETIMEOFFSET());
    DECLARE @ini datetimeoffset(3) = TODATETIMEOFFSET(CAST(@Desde AS datetime2(3)), @tz),
            @fin datetimeoffset(3) = TODATETIMEOFFSET(DATEADD(DAY, 1, CAST(@Hasta AS datetime2(3))), @tz);

    SELECT s.ProyectoClave, s.Sla, s.EnCurso, s.Incumplido, s.Abierto, s.TranscurridoMs,
           CAST(CASE WHEN s.EnCurso = 0 AND s.Fin >= @ini AND s.Fin < @fin THEN 1
                     WHEN s.EnCurso = 1 AND s.Incumplido = 1 AND s.Vencimiento >= @ini AND s.Vencimiento < @fin THEN 1
                     ELSE 0 END AS bit) AS Medido
    INTO #s
    FROM rpt.vSla s
    WHERE @Proyecto IS NULL OR s.ProyectoClave = @Proyecto;

    SELECT ProyectoClave AS Proyecto, Sla,
           SUM(CASE WHEN Medido = 1 THEN 1 ELSE 0 END) AS Ciclos,
           SUM(CASE WHEN Medido = 1 AND Incumplido = 0 THEN 1 ELSE 0 END) AS Cumplidos,
           SUM(CASE WHEN Medido = 1 AND Incumplido = 1 THEN 1 ELSE 0 END) AS Incumplidos,
           SUM(CASE WHEN EnCurso = 1 AND Incumplido = 0 AND Abierto = 1 THEN 1 ELSE 0 END) AS EnCursoAhora,
           CAST(100.0 * SUM(CASE WHEN Medido = 1 AND Incumplido = 0 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN Medido = 1 THEN 1 ELSE 0 END), 0) AS decimal(5,1)) AS PorcentajeCumplimiento,
           CAST(AVG(CASE WHEN Medido = 1 AND EnCurso = 0 THEN TranscurridoMs / 3600000.0 END) AS decimal(10,2)) AS HorasPromedio,
           SUM(CASE WHEN EnCurso = 1 AND Abierto = 0 THEN 1 ELSE 0 END) AS EnCursoEnTicketCerrado
    FROM #s
    GROUP BY ProyectoClave, Sla
    HAVING SUM(CASE WHEN Medido = 1 THEN 1 ELSE 0 END) > 0
        OR SUM(CASE WHEN EnCurso = 1 AND Abierto = 1 AND Incumplido = 0 THEN 1 ELSE 0 END) > 0
    ORDER BY ProyectoClave, Sla;

    IF @TicketsSinSla = 0 RETURN;
    SELECT t.ProyectoClave AS Proyecto, COUNT(*) AS TicketsCreados, SUM(t.SinSla) AS SinSla,
           CAST(100.0 * SUM(t.SinSla) / COUNT(*) AS decimal(5,1)) AS PorcentajeSinSla
    FROM (SELECT i.ProyectoClave,
                 CASE WHEN NOT EXISTS (SELECT 1 FROM ops.IssueSla x WHERE x.IssueSk = i.IssueSk) THEN 1 ELSE 0 END AS SinSla
          FROM rpt.vIssue i
          WHERE i.TipoProyecto = 'service_desk' AND i.Creado >= @ini AND i.Creado < @fin AND i.NivelJerarquia >= 0
            AND (@Proyecto IS NULL OR i.ProyectoClave = @Proyecto)) t
    GROUP BY t.ProyectoClave
    ORDER BY SinSla DESC, t.ProyectoClave;
END;
GO
