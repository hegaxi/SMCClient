import { useEffect, useState } from 'react';
import { api, ErrorApi } from '../api';
import { etiqueta, formatear, opcionesDeColumna } from '../formato';
import type { ConjuntoResultados, Fila, ValoresFormulario } from '../tipos';
import { AGREGACIONES, barrasDeResumen, calcularBarras, calcularIndicador, formatoIndicador, leerConfig, parametrosResumen, PROC_RESUMEN, usaResumen, type TipoWidget } from '../widgets';
import { BarrasHorizontales } from './BarrasHorizontales';
import { TablaResultados } from './TablaResultados';

interface Props {
  widget: Fila;
  edicion: boolean;
  primero: boolean;
  ultimo: boolean;
  etiquetasValores?: Map<string, Map<string, string>>;
  onAbrirConsulta: (nombre: string, valores: ValoresFormulario) => void;
  onSyncPendiente: () => void;
  onMover: (direccion: number) => void;
  onEditar: () => void;
  onQuitar: () => void;
}

/** Un widget: ejecuta la consulta de su filtro con los permisos de quien ve el tablero y la muestra según su tipo. */
export function WidgetVista({ widget, edicion, primero, ultimo, etiquetasValores, onAbrirConsulta, onSyncPendiente, onMover, onEditar, onQuitar }: Props) {
  const tipo = String(widget.Tipo) as TipoWidget;
  const config = leerConfig(widget.Configuracion);
  const procedimiento = String(widget.Procedimiento);
  const parametros = (() => {
    try { return JSON.parse(String(widget.ParametrosResueltos ?? '{}')) as Record<string, unknown>; } catch { return {}; }
  })();
  const puede = widget.PuedoEjecutar === true;
  // Búsqueda avanzada: barras e indicadores se calculan en SQL sobre todos los issues del filtro.
  const resumen = usaResumen(procedimiento, tipo, config);
  const [datos, setDatos] = useState<ConjuntoResultados | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [verTabla, setVerTabla] = useState(false);

  useEffect(() => {
    if (!puede) return;
    let vigente = true;
    api.ejecutar(resumen ? PROC_RESUMEN : procedimiento, resumen ? parametrosResumen(parametros, tipo, config) : parametros)
      .then((r) => vigente && setDatos(r.resultados[config.resultado ?? 0] ?? { columnas: [], filas: [], truncado: false }))
      .catch((e) => {
        if (!vigente) return;
        if (e instanceof ErrorApi && e.sincronizacionPendiente) onSyncPendiente();
        else setError(e instanceof Error ? e.message : 'No se pudo cargar.');
      });
    return () => { vigente = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [procedimiento, String(widget.ParametrosResueltos), String(widget.Configuracion), puede]);

  const texto = (columna: string) => (v: unknown) => {
    const op = etiquetasValores ? opcionesDeColumna(columna, etiquetasValores) : undefined;
    return typeof v === 'string' && op?.has(v) ? op.get(v)! : formatear(v, '');
  };

  let cuerpo;
  if (!puede) cuerpo = <p className="vacio">Sin permiso para esta consulta.</p>;
  else if (error) cuerpo = <p className="alerta" role="alert">{error}</p>;
  else if (!datos) cuerpo = <div className="cargando" aria-label="Cargando" />;
  else if (tipo === 'indicador' && resumen) {
    const f = datos.filas[0];
    const nombre = AGREGACIONES.find((a) => a.valor === config.agregacion)?.etiqueta ?? '';
    cuerpo = (
      <div className="kpi">
        <span className="kpi-valor">{formatoIndicador(typeof f?.Valor === 'number' ? f.Valor : null)}</span>
        <span className="kpi-detalle secundario">{nombre} de {String(f?.EtiquetaValor ?? '').toLowerCase()} · {Number(f?.Issues ?? 0).toLocaleString('es-MX')} issues</span>
      </div>
    );
  } else if (tipo === 'barras' && resumen) {
    const barras = barrasDeResumen(datos.filas);
    const grupo = String(datos.filas[0]?.EtiquetaGrupo ?? 'Grupo');
    const nombreValor = config.agregacion === 'conteo' ? 'Issues' : `${AGREGACIONES.find((a) => a.valor === config.agregacion)?.etiqueta ?? 'Suma'} de ${String(datos.filas[0]?.EtiquetaValor ?? '').toLowerCase()}`;
    cuerpo = verTabla ? (
      <TablaResultados conjunto={{ truncado: false, columnas: [{ nombre: grupo, tipo: 'nvarchar', nulo: true }, { nombre: nombreValor, tipo: 'decimal', nulo: true }, { nombre: 'Issues', tipo: 'int', nulo: true }],
        filas: datos.filas.map((f, i) => ({ [grupo]: barras[i].etiqueta, [nombreValor]: barras[i].valor, Issues: f.Issues })) }} nombreArchivo={String(widget.Titulo)} />
    ) : (
      <BarrasHorizontales barras={barras} titulo={String(widget.Titulo)} nombreValor={nombreValor}
                          porcentaje={config.agregacion === 'conteo' || config.agregacion === 'suma' || !config.agregacion} />
    );
  } else if (tipo === 'indicador') {
    const valor = calcularIndicador(datos, config);
    cuerpo = (
      <div className="kpi">
        <span className="kpi-valor">{formatoIndicador(valor)}</span>
        <span className="kpi-detalle secundario">
          {config.agregacion && config.agregacion !== 'conteo' && config.columna ? `${etiqueta(config.agregacion)} de ${etiqueta(config.columna).toLowerCase()}` : 'registros'}
        </span>
      </div>
    );
  } else if (tipo === 'barras') {
    const barras = calcularBarras(datos.filas, config, texto(config.etiqueta ?? ''));
    cuerpo = verTabla ? (
      <TablaResultados conjunto={{ truncado: false, columnas: [{ nombre: etiqueta(config.etiqueta ?? ''), tipo: 'nvarchar', nulo: true }, { nombre: etiqueta(config.valor ?? ''), tipo: 'decimal', nulo: true }],
        filas: barras.map((b) => ({ [etiqueta(config.etiqueta ?? '')]: b.etiqueta, [etiqueta(config.valor ?? '')]: b.valor })) }} nombreArchivo={String(widget.Titulo)} />
    ) : (
      <BarrasHorizontales barras={barras} titulo={String(widget.Titulo)} nombreValor={etiqueta(config.valor ?? '')} />
    );
  } else {
    const columnas = config.columnas?.length ? datos.columnas.filter((c) => config.columnas!.includes(c.nombre)) : datos.columnas;
    cuerpo = (
      <TablaResultados conjunto={{ ...datos, columnas, filas: datos.filas.slice(0, config.limite ?? 10) }} nombreArchivo={String(widget.Titulo)}
                       etiquetasValores={etiquetasValores} onAbrirClave={(c) => onAbrirConsulta('Issue_Detalle', { Clave: c })} />
    );
  }

  return (
    <section className={`widget ancho-${Number(widget.Ancho) || 2}`} aria-labelledby={`w-${String(widget.WidgetId)}`}>
      <header className="widget-encabezado">
        <div>
          <h3 id={`w-${String(widget.WidgetId)}`}>{String(widget.Titulo)}</h3>
          <button type="button" className="enlace secundario widget-filtro"
                  onClick={() => onAbrirConsulta(procedimiento, Object.fromEntries(Object.entries(parametros).map(([k, v]) => [k, String(v)])))}>
            {String(widget.Filtro)}
          </button>
        </div>
        <div className="widget-acciones">
          {tipo === 'barras' && datos && <button type="button" className="enlace" onClick={() => setVerTabla((v) => !v)}>{verTabla ? 'Ver barras' : 'Ver tabla'}</button>}
          {edicion && (
            <>
              <button type="button" className="icono" onClick={() => onMover(-1)} disabled={primero} aria-label={`Mover ${String(widget.Titulo)} antes`}>↑</button>
              <button type="button" className="icono" onClick={() => onMover(1)} disabled={ultimo} aria-label={`Mover ${String(widget.Titulo)} después`}>↓</button>
              <button type="button" className="icono" onClick={onEditar} aria-label={`Editar ${String(widget.Titulo)}`}>✎</button>
              <button type="button" className="icono" onClick={onQuitar} aria-label={`Quitar ${String(widget.Titulo)}`}>✕</button>
            </>
          )}
        </div>
      </header>
      <div className="widget-cuerpo">{cuerpo}</div>
    </section>
  );
}
