/* Roles de base de datos (se asignan a los usuarios de la API y del worker).
   smc_api : solo puede ejecutar procedimientos del esquema api (no lee tablas directamente).
   smc_sync: el worker; ejecuta procedimientos sync y lee la configuración. */
IF DATABASE_PRINCIPAL_ID('smc_api') IS NULL CREATE ROLE smc_api AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID('smc_sync') IS NULL CREATE ROLE smc_sync AUTHORIZATION dbo;
GO
GRANT EXECUTE ON SCHEMA::api TO smc_api;
-- El controlador lee los metadatos de los procedimientos (sys.parameters, propiedades extendidas).
GRANT VIEW DEFINITION ON SCHEMA::api TO smc_api;

GRANT EXECUTE ON SCHEMA::sync TO smc_sync;
GRANT SELECT  ON SCHEMA::cfg  TO smc_sync;
GRANT EXECUTE ON TYPE::sync.DocumentoTipo TO smc_sync;
GRANT EXECUTE ON TYPE::sync.IdTipo TO smc_sync;
GO
