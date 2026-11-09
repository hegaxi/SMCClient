import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ErrorApi } from '../api';
import { construirCuerpo, valoresIniciales } from '../formato';
import { accionDisponible, accionVisibleEnFila, reemplazar, valoresDeAccion } from '../acciones';
import type { AccionListado, Fila, ProcedimientoInfo, ResultadoEjecucion, ValoresFormulario } from '../tipos';
import { DialogoAccion } from './DialogoAccion';
import { Formulario } from './Formulario';
import { limpiarCacheListas } from './ListaOrigen';
import { GuardarFiltro } from './GuardarFiltro';
import { TablaResultados } from './TablaResultados';
import { ArbolResultados, esArbol } from './ArbolResultados';

interface Props {
  proc: ProcedimientoInfo;
  valoresUrl: ValoresFormulario;
  /** Abre otro procedimiento (p. ej. el detalle de un issue al hacer clic en su clave). */
  onNavegar: (nombre: string, valores: ValoresFormulario, reemplazar?: boolean) => void;
  puedeVerDetalle: boolean;
  onSyncPendiente: () => void;
  etiquetasValores?: Map<string, Map<string, string>>;
  /** Muestra "Guardar como filtro" (si el usuario tiene filtros y la consulta no es una acción). */
  puedeGuardarFiltro?: boolean;
  /** Catálogo del usuario: las acciones del listado solo aparecen si puede ejecutarlas. */
  catalogo?: ProcedimientoInfo[];
  /** Vistas propias de la interfaz a las que puede llevar una acción (p. ej. _restablecer). */
  vistasPropias?: string[];
}

/** Los maneja la paginación (botones Anterior / Siguiente), no el formulario. */
const PARAMETROS_PAGINACION = new Set(['Pagina', 'TamanoPagina']);

export function VistaProcedimiento({ proc, valoresUrl, onNavegar, puedeVerDetalle, onSyncPendiente, etiquetasValores, puedeGuardarFiltro, catalogo = [], vistasPropias = [] }: Props) {
  const [dialogo, setDialogo] = useState<{ accion: AccionListado; proc: ProcedimientoInfo; inicial: ValoresFormulario } | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);
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
        // Una acción pudo cambiar lo que ofrecen las listas (p. ej. un rol nuevo): se vuelven a pedir.
        if (proc.accion) limpiarCacheListas();
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

  // Acciones del listado (smc:acciones): "Nuevo …" arriba y Editar / Eliminar… en cada fila.
  const acciones = (proc.acciones ?? []).filter((a) => accionDisponible(a, catalogo, vistasPropias));
  const refrescar = () => void ejecutar(valores, false);
  const lanzar = async (a: AccionListado, fila?: Fila) => {
    const inicial = valoresDeAccion(a, fila);
    if (a.vista) { onNavegar(a.vista, inicial); return; }
    const destino = catalogo.find((p) => p.nombre === a.proc);
    if (!destino) return;
    if (!a.directo) { setDialogo({ accion: a, proc: destino, inicial }); return; }
    if (!window.confirm(a.confirmar ? reemplazar(a.confirmar, fila ?? {}) : `¿${a.etiqueta}?`)) return;
    setMensaje(null); setAviso(null);
    try {
      await api.ejecutar(destino.nombre, construirCuerpo(destino.parametros, inicial));
      limpiarCacheListas();
      setAviso(a.exito ? reemplazar(a.exito, { ...fila, ...inicial }) : 'Listo.');
      refrescar();
    } catch (e) {
      setMensaje(e instanceof Error ? e.message : 'No se pudo completar la acción.');
    }
  };
  const botonesFila = acciones.some((a) => a.fila)
    ? (f: Fila) => acciones.filter((a) => a.fila && accionVisibleEnFila(a, f)).map((a) => (
        <button key={a.etiqueta} type="button" className={a.peligro ? 'boton secundario-btn pequeno peligro' : 'boton secundario-btn pequeno'}
                onClick={() => void lanzar(a, f)}>{a.etiqueta}</button>
      ))
    : undefined;

  const abrirClave = puedeVerDetalle && proc.nombre !== 'Issue_Detalle'
    ? (clave: string) => onNavegar('Issue_Detalle', { Clave: clave })
    : undefined;

  return (
    <article className="vista">
      <header>
        <h1>{proc.titulo}</h1>
        {proc.descripcion && <p className="secundario">{proc.descripcion}</p>}
        {acciones.some((a) => !a.fila) && (
          <div className="barra-acciones">
            {acciones.filter((a) => !a.fila).map((a, i) => (
              <button key={a.etiqueta} type="button" className={i === 0 && a.proc ? 'boton' : 'boton secundario-btn'} onClick={() => void lanzar(a)}>
                {i === 0 && a.proc ? `+ ${a.etiqueta}` : a.etiqueta}
              </button>
            ))}
          </div>
        )}
      </header>

      <Formulario
        parametros={proc.parametros.filter((p) => !PARAMETROS_PAGINACION.has(p.nombre))}
        valores={valores}
        errores={errores}
        ocupado={ocupado}
        onCambio={cambiar}
        onEnviar={enviar}
        textoBoton={proc.accion ? 'Ejecutar' : 'Consultar'}
      >
        {puedeGuardarFiltro && !proc.accion && !guardando && (
          <button type="button" className="boton secundario-btn" onClick={() => { setGuardando(true); setAviso(null); }}>Guardar como filtro</button>
        )}
      </Formulario>
      {aviso && <p className="aviso" role="status">{aviso}</p>}

      {guardando && (
        <GuardarFiltro proc={proc} valores={valores}
                       onGuardado={(n) => { setGuardando(false); setAviso(`Filtro "${n}" guardado. Úselo en un tablero o en Mis filtros.`); }}
                       onCancelar={() => setGuardando(false)} />
      )}

      {mensaje && <p className="alerta" role="alert">{mensaje}</p>}

      {resultado && (
        <div className="resultados" aria-busy={ocupado}>
          <h2 ref={tituloResultados} tabIndex={-1} className="solo-lectores">Resultados</h2>
          {resultado.resultados.length === 0 && <p className="vacio">Listo. El procedimiento no devolvió datos.</p>}
          {resultado.resultados.map((c, i) => esArbol(c) ? (
            <ArbolResultados key={i} conjunto={c} titulo={proc.titulosResultados?.[i] ?? null}
                             nombreArchivo={`${proc.nombre}${resultado.resultados.length > 1 ? `_${i + 1}` : ''}`} onAbrirClave={abrirClave} />
          ) : (
            <TablaResultados
              key={i}
              conjunto={c}
              titulo={proc.titulosResultados?.[i] ?? (resultado.resultados.length > 1 ? `Resultado ${i + 1}` : null)}
              nombreArchivo={`${proc.nombre}${resultado.resultados.length > 1 ? `_${i + 1}` : ''}`}
              onAbrirClave={abrirClave}
              permitirFicha={i === 0 && proc.parametros.some((p) => !p.opcional && !p.salida)}
              textoVacio={resultado.resultados.length > 1 && i > 0 ? 'Sin registros.' : undefined}
              etiquetasValores={etiquetasValores}
              accionesFila={i === 0 ? botonesFila : undefined}
            />
          ))}
          {tienePaginas && total > tamano && (
            <nav className="paginacion" aria-label="Páginas">
              <button type="button" className="boton secundario-btn" disabled={pagina <= 1 || ocupado} onClick={() => irA(pagina - 1)}>← Anterior</button>
              <span aria-live="polite">Página {pagina} de {paginas} · {total.toLocaleString('es-MX')} en total</span>
              <button type="button" className="boton secundario-btn" disabled={pagina >= paginas || ocupado} onClick={() => irA(pagina + 1)}>Siguiente →</button>
            </nav>
          )}
        </div>
      )}
      {dialogo && (
        <DialogoAccion accion={dialogo.accion} proc={dialogo.proc} inicial={dialogo.inicial} onCerrar={() => setDialogo(null)}
                       onListo={(m) => { setDialogo(null); setAviso(m); refrescar(); }} />
      )}
    </article>
  );
}
