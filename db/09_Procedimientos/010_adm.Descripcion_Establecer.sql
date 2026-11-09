/* Crea o actualiza una propiedad extendida (MS_Description, smc:etiqueta, smc:permiso...) de un
   procedimiento o de uno de sus parámetros. El controlador la lee para armar la interfaz y la autorización. */
CREATE OR ALTER PROCEDURE adm.Descripcion_Establecer
    @Objeto    nvarchar(300),            -- 'api.Issues_Buscar'
    @Parametro sysname = NULL,           -- '@Proyecto' o NULL para el procedimiento
    @Nombre    sysname = N'MS_Description',
    @Valor     nvarchar(3750)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @esquema sysname = PARSENAME(@Objeto, 2), @obj sysname = PARSENAME(@Objeto, 1);
    IF OBJECT_ID(@Objeto) IS NULL THROW 50001, 'El objeto no existe.', 1;

    IF @Parametro IS NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(@Objeto) AND minor_id = 0 AND class = 1 AND name = @Nombre)
            EXEC sys.sp_updateextendedproperty @name = @Nombre, @value = @Valor, @level0type = N'SCHEMA', @level0name = @esquema, @level1type = N'PROCEDURE', @level1name = @obj;
        ELSE
            EXEC sys.sp_addextendedproperty @name = @Nombre, @value = @Valor, @level0type = N'SCHEMA', @level0name = @esquema, @level1type = N'PROCEDURE', @level1name = @obj;
    END
    ELSE
    BEGIN
        DECLARE @pid int = (SELECT parameter_id FROM sys.parameters WHERE object_id = OBJECT_ID(@Objeto) AND name = @Parametro);
        IF @pid IS NULL THROW 50002, 'El parámetro no existe.', 1;
        IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(@Objeto) AND minor_id = @pid AND class = 2 AND name = @Nombre)
            EXEC sys.sp_updateextendedproperty @name = @Nombre, @value = @Valor, @level0type = N'SCHEMA', @level0name = @esquema, @level1type = N'PROCEDURE', @level1name = @obj, @level2type = N'PARAMETER', @level2name = @Parametro;
        ELSE
            EXEC sys.sp_addextendedproperty @name = @Nombre, @value = @Valor, @level0type = N'SCHEMA', @level0name = @esquema, @level1type = N'PROCEDURE', @level1name = @obj, @level2type = N'PARAMETER', @level2name = @Parametro;
    END
END;
GO
