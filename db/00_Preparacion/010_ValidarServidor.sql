/* Valida versión y nivel de compatibilidad.
   JSON_VALUE con ruta variable requiere SQL Server 2017 (nivel 140) o posterior. */
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS int) < 14
    THROW 50000, 'SMCClient requiere SQL Server 2017 o posterior (recomendado 2019+).', 1;

IF (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) < 140
BEGIN
    DECLARE @sql nvarchar(200) = N'ALTER DATABASE ' + QUOTENAME(DB_NAME()) + N' SET COMPATIBILITY_LEVEL = 150;';
    EXEC (@sql);
END;
GO
