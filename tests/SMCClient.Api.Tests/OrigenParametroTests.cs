using SMCClient.Api.Procedimientos;
using Xunit;

namespace SMCClient.Api.Tests;

/// <summary>smc:origen: lista de un parámetro que sale de otro procedimiento, con parámetros (listas dependientes).</summary>
public class OrigenParametroTests
{
    [Fact]
    public void Lee_procedimiento_y_columnas()
    {
        var o = CatalogoProcedimientos.Origen("Proyectos_Listar:Clave:Clave:Nombre", libre: false)!;
        Assert.Equal("Proyectos_Listar", o.Procedimiento);
        Assert.Equal(("Clave", "Clave", "Nombre"), (o.Valor, o.Etiqueta, o.Descripcion));
        Assert.Null(o.Parametros);
    }

    [Fact]
    public void Lee_los_parametros_de_una_lista_dependiente()
    {
        var o = CatalogoProcedimientos.Origen("Sprints_Listar(Proyecto=@Proyecto, Estado=active):Valor:Etiqueta:Detalle", libre: false)!;
        Assert.Equal("Sprints_Listar", o.Procedimiento);
        Assert.Equal("@Proyecto", o.Parametros!["Proyecto"]);
        Assert.Equal("active", o.Parametros["estado"]);   // sin distinguir mayúsculas
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("SoloProcedimiento")]
    [InlineData("Proc;DROP:Valor")]          // el nombre debe ser un identificador
    public void Ignora_un_origen_invalido(string? valor) => Assert.Null(CatalogoProcedimientos.Origen(valor, libre: false));
}
