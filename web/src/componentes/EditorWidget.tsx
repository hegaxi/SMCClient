import { useEffect, useState, type FormEvent } from 'react';
import { api, ErrorApi } from '../api';
import { esNumero, etiqueta } from '../formato';
import type { ColumnaInfo, Fila, ProcedimientoInfo } from '../tipos';
import { AGREGACIONES, leerConfig, type ConfigWidget, type TipoWidget } from '../widgets';

interface Props {
  tableroId: number;
  widget?: Fila;
  filtros: Fila[];
  procs: ProcedimientoInfo[];
  onGuardado: () => void;
  onCancelar: () => void;
}

const tipoBase = (t: string) => t.replace(/\(.*$/, '');

/** Agregar o editar un widget: título, filtro, tipo y, según el tipo, qué columnas usar (salen de los metadatos de la consulta). */
export function EditorWidget({ tableroId, widget, filtros, procs, onGuardado, onCancelar }: Props) {
  const usables = filtros.filter((f) => f.PuedoUsar === true);
  const [titulo, setTitulo] = useState(String(widget?.Titulo ?? ''));
  const [filtroId, setFiltroId] = useState(String(widget?.FiltroId ?? usables[0]?.FiltroId ?? ''));
  const [tipo, setTipo] = useState<TipoWidget>((widget?.Tipo as TipoWidget) ?? 'indicador');
  const [ancho, setAncho] = useState(String(widget?.Ancho ?? 2));
  const [config, setConfig] = useState<ConfigWidget>(() => leerConfig(widget?.Configuracion) ?? {});
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const filtro = usables.find((f) => String(f.FiltroId) === filtroId);
  const deMetadatos = procs.find((p) => p.nombre === filtro?.Procedimiento)?.columnas ?? null;

  // Consultas con columnas variables (la búsqueda avanzada): se ejecuta el filtro una vez para conocerlas.
  const [dinamicas, setDinamicas] = useState<{ filtroId: string; columnas: ColumnaInfo[] } | null>(null);
  const procFiltro = filtro ? String(filtro.Procedimiento) : null;
  const parametrosFiltro = filtro ? String(filtro.ParametrosResueltos ?? '{}') : null;
  useEffect(() => {
    if (!procFiltro || deMetadatos || dinamicas?.filtroId === filtroId) return;
    let vigente = true;
    let parametros: Record<string, unknown> = {};
    try { parametros = JSON.parse(parametrosFiltro ?? '{}'); } catch { /* sin parámetros */ }
    api.ejecutar(procFiltro, parametros)
      .then((r) => vigente && setDinamicas({ filtroId, columnas: r.resultados[0]?.columnas ?? [] }))
      .catch(() => vigente && setDinamicas({ filtroId, columnas: [] }));
    return () => { vigente = false; };
  }, [procFiltro, parametrosFiltro, deMetadatos, filtroId, dinamicas?.filtroId]);

  const columnas = (deMetadatos ?? (dinamicas?.filtroId === filtroId ? dinamicas.columnas : [])).filter((c) => c.nombre !== 'TotalFilas');
  const numericas = columnas.filter((c) => esNumero(tipoBase(c.tipo)));
  const cambiar = (c: Partial<ConfigWidget>) => setConfig((x) => ({ ...x, ...c }));

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setOcupado(true);
    const limpio: ConfigWidget =
      tipo === 'indicador' ? { agregacion: config.agregacion ?? 'conteo', ...(config.agregacion && config.agregacion !== 'conteo' ? { columna: config.columna } : {}) }
      : tipo === 'barras' ? { etiqueta: config.etiqueta, valor: config.valor, limite: config.limite ?? 10 }
      : { limite: config.limite ?? 10, ...(config.columnas?.length ? { columnas: config.columnas } : {}) };
    try {
      await api.ejecutar('Widget_Guardar', {
        ...(widget ? { WidgetId: widget.WidgetId } : {}),
        TableroId: tableroId, Titulo: titulo, FiltroId: Number(filtroId), Tipo: tipo, Configuracion: JSON.stringify(limpio), Ancho: Number(ancho),
      });
      onGuardado();
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo guardar el widget.');
    } finally {
      setOcupado(false);
    }
  };

  if (usables.length === 0) {
    return (
      <div className="formulario">
        <p>Primero guarde un filtro: abra una consulta, elija sus valores y use <strong>Guardar como filtro</strong>.</p>
        <button type="button" className="boton secundario-btn" onClick={onCancelar}>Cerrar</button>
      </div>
    );
  }

  const selector = (id: string, texto: string, valor: string | undefined, opciones: { nombre: string }[], alCambiar: (v: string) => void) => (
    <div className="campo">
      <label htmlFor={id}>{texto} <span className="obligatorio" aria-hidden="true">*</span></label>
      <select id={id} value={valor ?? ''} onChange={(e) => alCambiar(e.target.value)} required>
        <option value="">Seleccione…</option>
        {opciones.map((c) => <option key={c.nombre} value={c.nombre}>{etiqueta(c.nombre)}</option>)}
      </select>
    </div>
  );

  return (
    <form className="formulario editor-widget" onSubmit={enviar} aria-label={widget ? 'Editar widget' : 'Agregar widget'}>
      <h3>{widget ? 'Editar widget' : 'Agregar widget'}</h3>
      <div className="campos">
        <div className="campo">
          <label htmlFor="w-titulo">Título <span className="obligatorio" aria-hidden="true">*</span></label>
          <input id="w-titulo" value={titulo} onChange={(e) => setTitulo(e.target.value)} required maxLength={150} />
        </div>
        <div className="campo">
          <label htmlFor="w-filtro">Filtro <span className="obligatorio" aria-hidden="true">*</span></label>
          <select id="w-filtro" value={filtroId} onChange={(e) => { setFiltroId(e.target.value); setConfig({}); }} required>
            {usables.map((f) => <option key={String(f.FiltroId)} value={String(f.FiltroId)}>{String(f.Nombre)} · {String(f.Consulta)}</option>)}
          </select>
        </div>
        <div className="campo">
          <label htmlFor="w-tipo">Mostrar como</label>
          <select id="w-tipo" value={tipo} onChange={(e) => setTipo(e.target.value as TipoWidget)}>
            <option value="indicador">Indicador (un número)</option>
            <option value="barras">Barras</option>
            <option value="tabla">Tabla</option>
          </select>
        </div>
        <div className="campo">
          <label htmlFor="w-ancho">Ancho</label>
          <select id="w-ancho" value={ancho} onChange={(e) => setAncho(e.target.value)}>
            <option value="1">1/4</option><option value="2">1/2</option><option value="3">3/4</option><option value="4">Completo</option>
          </select>
        </div>

        {tipo === 'indicador' && (
          <>
            <div className="campo">
              <label htmlFor="w-agregacion">Cálculo</label>
              <select id="w-agregacion" value={config.agregacion ?? 'conteo'} onChange={(e) => cambiar({ agregacion: e.target.value as ConfigWidget['agregacion'] })}>
                {AGREGACIONES.map((a) => <option key={a.valor} value={a.valor}>{a.etiqueta}</option>)}
              </select>
            </div>
            {config.agregacion && config.agregacion !== 'conteo' &&
              selector('w-columna', 'Columna', config.columna, config.agregacion === 'primero' ? columnas : numericas, (v) => cambiar({ columna: v }))}
          </>
        )}
        {tipo === 'barras' && (
          <>
            {selector('w-etiqueta', 'Agrupar por', config.etiqueta, columnas, (v) => cambiar({ etiqueta: v }))}
            {selector('w-valor', 'Valor', config.valor, numericas, (v) => cambiar({ valor: v }))}
          </>
        )}
        {tipo !== 'indicador' && (
          <div className="campo">
            <label htmlFor="w-limite">{tipo === 'barras' ? 'Máximo de barras' : 'Máximo de filas'}</label>
            <input id="w-limite" type="number" min={1} max={50} value={config.limite ?? 10} onChange={(e) => cambiar({ limite: Number(e.target.value) })} />
          </div>
        )}
      </div>
      {tipo === 'tabla' && columnas.length > 0 && (
        <fieldset className="columnas-tabla">
          <legend>Columnas (ninguna marcada = todas)</legend>
          {columnas.map((c) => (
            <label key={c.nombre}>
              <input type="checkbox" checked={config.columnas?.includes(c.nombre) ?? false}
                     onChange={(e) => cambiar({ columnas: e.target.checked ? [...(config.columnas ?? []), c.nombre] : (config.columnas ?? []).filter((x) => x !== c.nombre) })} />
              {etiqueta(c.nombre)}
            </label>
          ))}
        </fieldset>
      )}
      {error && <p className="alerta" role="alert">{error}</p>}
      <div className="acciones">
        <button type="submit" className="boton" disabled={ocupado}>{ocupado ? 'Guardando…' : 'Guardar widget'}</button>
        <button type="button" className="boton secundario-btn" onClick={onCancelar}>Cancelar</button>
      </div>
    </form>
  );
}
