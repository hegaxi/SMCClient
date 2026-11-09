/* Regla de copias más estricta (sync.Worklog_Atribuir): el original se busca por hora de creación (la copia se crea
   segundos después) y por la misma hora de inicio o el mismo tiempo, ya no por "mismo tiempo a ±2 h".
   El índice de búsqueda cambia de llaves (lo vuelve a crear 06_Indices) y se recalculan las copias (095 recalcula
   donde EsCopia es NULL). */
IF INDEXPROPERTY(OBJECT_ID('ops.Worklog'), 'IX_ops_Worklog_Copia', 'IndexId') IS NOT NULL DROP INDEX IX_ops_Worklog_Copia ON ops.Worklog;
GO
UPDATE ops.Worklog SET EsCopia = NULL WHERE EsCopia IS NOT NULL;
GO
