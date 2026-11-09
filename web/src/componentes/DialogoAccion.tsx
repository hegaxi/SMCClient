import { useEffect, useRef, useState } from 'react';
import { api, ErrorApi } from '../api';
import { reemplazar } from '../acciones';
import { construirCuerpo } from '../formato';
import type { AccionListado, ProcedimientoInfo, ValoresFormulario } from '../tipos';
import { Formulario } from './Formulario';
import { limpiarCacheListas } from './ListaOrigen';

interface Props {
  accion: AccionListado;
  /** Procedimiento que ejecuta la acción (su formulario se arma con sus parámetros). */
  proc: ProcedimientoInfo;
  inicial: ValoresFormulario;
  onCerrar: () => void;
  /** Terminó bien: mensaje para el usuario. */
  onListo: (mensaje: string) => void;
}

/**
 * Formulario de una acción de un listado (Nuevo / Editar) en una ventana sobre el listado: no se pierde de vista lo que
 * se estaba viendo y al guardar el listado se actualiza. Escape o "Cancelar" cierran; el foco vuelve al botón que la abrió.
 */
export function DialogoAccion({ accion, proc, inicial, onCerrar, onListo }: Props) {
  const [valores, setValores] = useState<ValoresFormulario>(inicial);
  const [errores, setErrores] = useState<Record<string, string[]>>({});
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const caja = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const anterior = document.activeElement as HTMLElement | null;
    // Primer campo que se puede cambiar.
    caja.current?.querySelector<HTMLElement>('input:not([readonly]), select, textarea')?.focus();
    const alTeclear = (e: globalThis.KeyboardEvent) => { if (e.key === 'Escape') onCerrar(); };
    window.addEventListener('keydown', alTeclear);
    return () => { window.removeEventListener('keydown', alTeclear); anterior?.focus?.(); };
  }, [onCerrar]);

  const enviar = async () => {
    setOcupado(true); setErrores({}); setMensaje(null);
    try {
      await api.ejecutar(proc.nombre, construirCuerpo(proc.parametros, valores));
      limpiarCacheListas();
      onListo(accion.exito ? reemplazar(accion.exito, valores) : 'Listo.');
    } catch (e) {
      if (e instanceof ErrorApi && e.problema.errors) setErrores(e.problema.errors);
      setMensaje(e instanceof Error ? e.message : 'No se pudo guardar.');
    } finally {
      setOcupado(false);
    }
  };

  const tituloId = `dialogo-${proc.nombre}`;
  return (
    <div className="velo-dialogo" onMouseDown={(e) => { if (e.target === e.currentTarget) onCerrar(); }}>
      <div ref={caja} className="dialogo" role="dialog" aria-modal="true" aria-labelledby={tituloId}>
        <header className="dialogo-encabezado">
          <h2 id={tituloId}>{accion.etiqueta}</h2>
          <button type="button" className="enlace cerrar-dialogo" aria-label="Cerrar" onClick={onCerrar}>✕</button>
        </header>
        {proc.descripcion && <p className="secundario">{proc.descripcion}</p>}
        {mensaje && <p className="alerta" role="alert">{mensaje}</p>}
        <Formulario parametros={proc.parametros} valores={valores} errores={errores} ocupado={ocupado}
                    onCambio={(n, v) => { setValores((x) => ({ ...x, [n]: v })); setErrores(({ [n]: _, ...resto }) => resto); }}
                    onEnviar={() => void enviar()} textoBoton="Guardar" textoOcupado="Guardando…" bloqueados={accion.bloquear}
                    textoSinValor="Sin cambio">
          <button type="button" className="boton secundario-btn" onClick={onCerrar}>Cancelar</button>
        </Formulario>
      </div>
    </div>
  );
}
