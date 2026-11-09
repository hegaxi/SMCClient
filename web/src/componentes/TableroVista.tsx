import { useCallback, useEffect, useState } from 'react';
import { api, ErrorApi } from '../api';
import type { Fila, ProcedimientoInfo, ValoresFormulario } from '../tipos';
import { EditorWidget } from './EditorWidget';
import { WidgetVista } from './WidgetVista';

interface Props {
  tableroId: number;
  procs: ProcedimientoInfo[];
  /** Tiene la opción "Crear y editar tableros". */
  puedeEditar?: boolean;
  etiquetasValores?: Map<string, Map<string, string>>;
  onAbrirConsulta: (nombre: string, valores: ValoresFormulario) => void;
  onEditarTablero: (tablero: Fila) => void;
  onEliminado: () => void;
  onCambio: () => void;
  onSyncPendiente: () => void;
}

/** Un tablero: sus widgets en una cuadrícula de 4 columnas. El propietario puede agregar, editar, ordenar y quitar. */
export function TableroVista({ tableroId, procs, puedeEditar = true, etiquetasValores, onAbrirConsulta, onEditarTablero, onEliminado, onCambio, onSyncPendiente }: Props) {
  const [tablero, setTablero] = useState<Fila | null>(null);
  const [widgets, setWidgets] = useState<Fila[]>([]);
  const [filtros, setFiltros] = useState<Fila[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [edicion, setEdicion] = useState(false);
  const [editor, setEditor] = useState<Fila | 'nuevo' | null>(null);
  const [version, setVersion] = useState(0); // "Actualizar" vuelve a consultar los datos

  const cargar = useCallback(async () => {
    try {
      const r = await api.ejecutar('Tablero_Obtener', { TableroId: tableroId });
      setTablero(r.resultados[0]?.filas[0] ?? null);
      setWidgets(r.resultados[1]?.filas ?? []);
      setError(null);
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo abrir el tablero.');
    }
  }, [tableroId]);

  useEffect(() => { void cargar(); }, [cargar]);

  useEffect(() => {
    if (edicion) api.ejecutar('Filtros_Listar').then((r) => setFiltros(r.resultados[0]?.filas ?? [])).catch(() => setFiltros([]));
  }, [edicion]);

  const accion = async (nombre: string, parametros: Record<string, unknown>, confirmar?: string) => {
    if (confirmar && !window.confirm(confirmar)) return false;
    try {
      await api.ejecutar(nombre, parametros);
      return true;
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo completar la acción.');
      return false;
    }
  };

  if (error && !tablero) return <article className="vista"><p className="alerta" role="alert">{error}</p></article>;
  if (!tablero) return <article className="vista"><div className="cargando" aria-label="Cargando" /></article>;
  const esMio = tablero.EsMio === true;

  return (
    <article className="vista tablero">
      <header className="tablero-encabezado">
        <div>
          <h1>{String(tablero.Nombre)}</h1>
          <p className="secundario">
            {tablero.Descripcion ? `${String(tablero.Descripcion)} · ` : ''}
            {esMio ? 'Su tablero' : `De ${String(tablero.Propietario)}`}
          </p>
        </div>
        <div className="acciones">
          <button type="button" className="boton secundario-btn" onClick={() => setVersion((v) => v + 1)}>Actualizar</button>
          <button type="button" className="boton secundario-btn"
                  onClick={async () => { if (await accion('Tablero_Inicio', { TableroId: tablero.EsInicio ? null : tableroId })) { await cargar(); onCambio(); } }}>
            {tablero.EsInicio ? 'Quitar de inicio' : 'Usar como inicio'}
          </button>
          {esMio && puedeEditar && (
            <>
              <button type="button" className={edicion ? 'boton' : 'boton secundario-btn'} onClick={() => { setEdicion((e) => !e); setEditor(null); }}>
                {edicion ? 'Terminar edición' : 'Editar'}
              </button>
              {edicion && <button type="button" className="boton secundario-btn" onClick={() => onEditarTablero(tablero)}>Nombre y compartir</button>}
              {edicion && (
                <button type="button" className="boton secundario-btn peligro"
                        onClick={async () => { if (await accion('Tablero_Eliminar', { TableroId: tableroId }, `¿Eliminar el tablero "${String(tablero.Nombre)}" y sus widgets?`)) onEliminado(); }}>
                  Eliminar tablero
                </button>
              )}
            </>
          )}
        </div>
      </header>

      {error && <p className="alerta" role="alert">{error}</p>}

      {edicion && editor && (
        <EditorWidget tableroId={tableroId} widget={editor === 'nuevo' ? undefined : editor} filtros={filtros} procs={procs}
                      onGuardado={async () => { setEditor(null); await cargar(); onCambio(); }} onCancelar={() => setEditor(null)} />
      )}
      {edicion && !editor && <button type="button" className="boton agregar-widget" onClick={() => setEditor('nuevo')}>Agregar widget</button>}

      {widgets.length === 0 ? (
        <p className="vacio">{esMio ? 'Este tablero no tiene widgets. Use Editar → Agregar widget.' : 'Este tablero aún no tiene widgets.'}</p>
      ) : (
        <div className="cuadricula">
          {widgets.map((w, i) => (
            <WidgetVista
              key={`${String(w.WidgetId)}-${version}-${String(w.Configuracion)}-${String(w.FiltroId)}`}
              widget={w}
              edicion={edicion}
              primero={i === 0}
              ultimo={i === widgets.length - 1}
              etiquetasValores={etiquetasValores}
              onAbrirConsulta={onAbrirConsulta}
              onSyncPendiente={onSyncPendiente}
              onMover={async (d) => { if (await accion('Widget_Mover', { WidgetId: w.WidgetId, Direccion: d })) await cargar(); }}
              onEditar={() => setEditor(w)}
              onQuitar={async () => { if (await accion('Widget_Eliminar', { WidgetId: w.WidgetId }, `¿Quitar el widget "${String(w.Titulo)}"?`)) { await cargar(); onCambio(); } }}
            />
          ))}
        </div>
      )}
    </article>
  );
}
