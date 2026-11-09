using SMCClient.Api.Procedimientos;
using Xunit;

namespace SMCClient.Api.Tests;

public class EncabezadoProcedimientoTests
{
    [Fact]
    public void Detecta_los_parametros_con_valor_por_omision()
    {
        const string definicion = """
            /* Comentario con @Falso = 1 que no cuenta */
            CREATE OR ALTER PROCEDURE api.Ejemplo
                @Desde        date,                       -- obligatorio, @Comentado = 3
                @Proyecto     varchar(50)  = NULL,
                @Texto        nvarchar(200) = N'a, b',
                @Monto        decimal(9,2) = 1.5,
                @Salida       int OUTPUT,
                @Hasta        date
            AS
            BEGIN
                DECLARE @Interna int = 5;
            END
            """;

        var conDefault = CatalogoProcedimientos.ParametrosConValorPorOmision(definicion);

        Assert.Equal(new[] { "Monto", "Proyecto", "Texto" }, conDefault.OrderBy(x => x));
    }

    [Fact]
    public void Lee_el_valor_por_omision_como_texto()
    {
        const string definicion = """
            CREATE OR ALTER PROCEDURE api.Ejemplo
                @Nivel        varchar(10) = 'tarea',    -- tarea | epica
                @Detalle      bit = 1,
                @Proyecto     varchar(50) = NULL,
                @Texto        nvarchar(200) = N'a, b',
                @Comilla      nvarchar(20) = N'l''x',
                @Desde        date
            AS SELECT 1;
            """;

        var v = CatalogoProcedimientos.ValoresPorOmision(definicion);

        Assert.Equal("tarea", v["Nivel"]);
        Assert.Equal("1", v["Detalle"]);
        Assert.True(v.ContainsKey("Proyecto"));
        Assert.Null(v["Proyecto"]);
        Assert.Equal("a, b", v["Texto"]);
        Assert.Equal("l'x", v["Comilla"]);
        Assert.False(v.ContainsKey("Desde"));
    }

    [Fact]
    public void Procedimiento_sin_parametros() =>
        Assert.Empty(CatalogoProcedimientos.ParametrosConValorPorOmision("CREATE PROCEDURE api.X AS SELECT 1;"));
}
