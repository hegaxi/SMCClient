/* Capas de la base de datos (de la fuente al usuario):
   cfg  configuración editable (fuentes, entidades, reglas de roles de campo)
   meta catálogo descubierto en Jira (campos y su historial de cambios)
   raw  documentos JSON tal como llegan de Jira (permite reprocesar sin volver a llamar a Jira)
   sync control de la sincronización (ejecuciones, marcas de agua, candados, eventos)
   ops  modelo canónico limpio (issues, worklogs, SLA, sprints...)
   rpt  vistas de lectura sobre ops
   api  ÚNICOS procedimientos que expone el controlador */
IF SCHEMA_ID('cfg')  IS NULL EXEC ('CREATE SCHEMA cfg  AUTHORIZATION dbo;');
IF SCHEMA_ID('meta') IS NULL EXEC ('CREATE SCHEMA meta AUTHORIZATION dbo;');
IF SCHEMA_ID('raw')  IS NULL EXEC ('CREATE SCHEMA raw  AUTHORIZATION dbo;');
IF SCHEMA_ID('sync') IS NULL EXEC ('CREATE SCHEMA sync AUTHORIZATION dbo;');
IF SCHEMA_ID('ops')  IS NULL EXEC ('CREATE SCHEMA ops  AUTHORIZATION dbo;');
IF SCHEMA_ID('rpt')  IS NULL EXEC ('CREATE SCHEMA rpt  AUTHORIZATION dbo;');
IF SCHEMA_ID('api')  IS NULL EXEC ('CREATE SCHEMA api  AUTHORIZATION dbo;');
GO
