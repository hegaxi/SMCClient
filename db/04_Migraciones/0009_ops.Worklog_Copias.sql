/* Worklogs COPIADOS por Automation for Jira. En smco la automatización replica cada worklog que una persona registra
   en una subtarea hacia su tarea, su épica y el ticket de la OC en la mesa de servicio (mismo tiempo, creado al mismo
   minuto). Sumarlos junto con el original contaba el mismo trabajo dos, tres o cuatro veces. Se marcan al integrar
   (sync.Worklog_Atribuir) y los reportes los excluyen de los totales. Se calculan en 11_DatosSemilla/095. */
IF COL_LENGTH('ops.Worklog', 'EsCopia') IS NULL
    ALTER TABLE ops.Worklog ADD EsCopia bit NULL, CopiaDeWorklogId varchar(30) NULL;
GO
IF COL_LENGTH('ops.IssueResumen', 'SegCopiaPropios') IS NULL
    ALTER TABLE ops.IssueResumen ADD SegCopiaPropios bigint NULL, SegCopiaArbol bigint NULL;
GO
-- Los índices con las columnas nuevas los vuelve a crear 06_Indices.
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_IssueDet', 'IndexId') IS NOT NULL DROP INDEX IX_ops_Worklog_IssueDet ON ops.Worklog;
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_InicioDet', 'IndexId') IS NOT NULL DROP INDEX IX_ops_Worklog_InicioDet ON ops.Worklog;
GO
