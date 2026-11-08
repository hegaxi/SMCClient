import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ErrorApi } from '../api';
import { construirCuerpo, valoresIniciales } from '../formato';
import type { ProcedimientoInfo, ResultadoEjecucion, ValoresFormulario } from '../tipos';
import { Formulario } from './Formulario';
import { TablaResultados } from './TablaResultados';

interface Props {
  proc: ProcedimientoInfo;
  valoresUrl: ValoresFormulario;
  /** Abre otro procedimiento (p. ej. el detalle de un issue al hacer clic en su clave). */
  onNavegar: (nombre: string, valores: ValoresFormulario, reemplazar?: boolean) => void;
  puedeVerDetalle: boolean;
  onSyncPendiente: () => void;
  etiquetasValores?: Map<string, Map<string, string>>;
}

/** Los maneja la paginación (botones Anterior / Siguiente), no el formulario. */
const PARAMETROS_PAGINACION = new Set(['Pagina', 'TamanoPagina']);

export function VistaProcedimiento({ proc, valoresUrl, onNavegar, puedeVerDetalle, onSyncPendiente, etiquetasValores }: Props) {
  const [valores, setValores] = useState<ValoresFormulario>(() => ({ ...valoresIniciales(proc.parametros), ...valoresUrl }));
  const [errores, setErrores] = useState<Record<string, string[]>>({});
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [resultado, setResultado] = useState<ResultadoEjecucion | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const tituloResultados = useRef<HTMLHeadingElement>(null);

  const ejecutar = useCallback(
    async (v: ValoresFormulario, enfocar = true) => {
      setOcupado(true);
      setErrores({});
      setMensaje(null);
      // La consulta queda en la dirección del navegador: se puede compartir o volver con "Atrás".
      onNavegar(proc.nombre, Object.fromEntries(Object.entries(v).filter(([, x]) => x !== '')), true);
      try {
        setResultado(await api.ejecutar(proc.nombre, construirCuerpo(proc.parametros, v)));
        if (enfocar) setTimeout(() => tituloResultados.current?.focus(), 0);
      } catch (e) {
        setResultado(null);
        if (e instanceof ErrorApi && e.sincronizacionPendiente) onSyncPendiente();
        else if (e instanceof ErrorApi && e.problema.errors) {
          setErrores(e.problema.errors);
          setMensaje(e.message);
        } else setMensaje(e instanceof Error ? e.message : 'Ocurrió un error inesperado.');
      } finally {
        setOcupado(false);
      }
    },
    [proc, onNavegar, onSyncPendiente],
  );

  // Una consulta (no una acción) corre al abrirla si no le faltan datos obligatorios.
  const yaCorrio = useRef(false);
  useEffect(() => {
    if (yaCorrio.current || proc.accion) return;
    yaCorrio.current = true;
    const completos = proc.parametros.every((p) => p.opcional || p.salida || (valores[p.nombre] ?? '') !== '');
    if (completos) void ejecutar(valores, false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const enviar = () => {
    if (proc.accion && !window.confirm(`¿Ejecutar "${proc.titulo}"?`)) return;
    void ejecutar({ ...valores, ...(tienePaginas ? { Pagina: '' } : {}) });
  };

  const cambiar = (nombre: string, valor: string) => {
    setValores((v) => ({ ...v, [nombre]: valor }));
    setErrores((e) => {
      const { [nombre]: _, ...resto } = e;
      return resto;
    });
  };

  // Paginación para procedimientos con @Pagina / @TamanoPagina que devuelven TotalFilas.
  const tienePaginas = proc.parametros.some((p) => p.nombre === 'Pagina');
  const total = Number(resultado?.resultados[0]?.filas[0]?.TotalFilas ?? 0);
  const pagina = Number(valores.Pagina || 1);
  const tamano = Number(valores.TamanoPagina || 50);
  const paginas = Math.max(1, Math.ceil(total / tamano));
  const irA = (n: number) => {
    const v = { ...valores, Pagina: String(n) };
    setValores(v);
    void ejecutar(v);
  };

  const abrirClave = puedeVerDetalle && proc.nombre !== 'Issue_Detalle'
    ? (clave: string) => onNavegar('Issue_Detalle', { Clave: clave })
    : undefined;

  return (
    <article className="vista">
      <header>
        <h1>{proc.titulo}</h1>
        {proc.descripcion && <p className="secundario">{proc.descripcion}</p>}
      </header>

      <Formulario
        parametros={proc.parametros.filter((p) => !PARAMETROS_PAGINACION.has(p.nombre))}
        valores={valores}
        errores={errores}
        ocupado={ocupado}
        onCambio={cambiar}
        onEnviar={enviar}
        textoBoton={proc.accion ? 'Ejecutar' : 'Consultar'}
      />

      {mensaje && <p className="alerta" role="alert">{mensaje}</p>}

      {resultado && (
        <div className="resultados" aria-busy={ocupado}>
          <h2 ref={tituloResultados} tabIndex={-1} className="solo-lectores">Resultados</h2>
          {resultado.resultados.length === 0 && <p className="vacio">Listo. El procedimiento no devolvió datos.</p>}
          {resultado.resultados.map((c, i) => (
            <TablaResultados
              key={i}
              conjunto={c}
              titulo={proc.titulosResultados?.[i] ?? (resultado.resultados.length > 1 ? `Resultado ${i + 1}` : null)}
              nombreArchivo={`${proc.nombre}${resultado.resultados.length > 1 ? `_${i + 1}` : ''}`}
              onAbrirClave={abrirClave}
              permitirFicha={i === 0 && proc.parametros.some((p) => !p.opcional && !p.salida)}
              etiquetasValores={etiquetasValores}
            />
          ))}
          {tienePaginas && total > tamano && (
            <nav className="paginacion" aria-label="Páginas">
              <button type="button" className="boton secundario-btn" disabled={pagina <= 1 || ocupado} onClick={() => irA(pagina - 1)}>Anterior</button>
              <span>Página {pagina} de {paginas} · {total.toLocaleString('es-MX')} en total</span>
              <button type="button" className="boton secundario-btn" disabled={pagina >= paginas || ocupado} onClick={() => irA(pagina + 1)}>Siguiente</button>
            </nav>
          )}
        </div>
      )}
    </article>
  );
}
