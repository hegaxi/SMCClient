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
    public void Procedimiento_sin_parametros() =>
        Assert.Empty(CatalogoProcedimientos.ParametrosConValorPorOmision("CREATE PROCEDURE api.X AS SELECT 1;"));
}
