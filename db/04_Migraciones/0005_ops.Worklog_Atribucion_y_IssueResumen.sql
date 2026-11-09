/* Datos derivados calculados al integrar (antes se calculaban en cada consulta; la prueba de carga con 500 000
   worklogs tardaba de 6 s a más de 10 min). Agrega la atribución a ops.Worklog; la tabla ops.IssueResumen la crea
   03_Tablas. Los valores se calculan en 11_DatosSemilla/095 (cuando faltan), porque los procedimientos que los
   calculan se crean después de las migraciones. Los índices de worklogs se rehacen con las columnas nuevas. */
IF COL_LENGTH('ops.Worklog', 'EsAutomatico') IS NULL
    ALTER TABLE ops.Worklog ADD EsAutomatico bit NULL, AtribuidoAId varchar(128) NULL, MetodoAtribucion varchar(20) NULL;
GO
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_Issue', 'IndexId') IS NOT NULL DROP INDEX IX_ops_Worklog_Issue ON ops.Worklog;
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_Inicio', 'IndexId') IS NOT NULL DROP INDEX IX_ops_Worklog_Inicio ON ops.Worklog;
GO
