import { useState } from 'react';
import type { Fila } from '../tipos';
import { formatear } from '../formato';

const NOMBRES: Record<string, string> = {
  campo: 'Catálogo de campos',
  estado: 'Estados',
  proyecto: 'Proyectos',
  issue: 'Historias y tickets',
  changelog: 'Historial de cambios',
  worklog: 'Tiempo registrado',
  worklog_eliminado: 'Tiempo eliminado',
  sla: 'SLA de mesa de ayuda',
  comentario: 'Comentarios',
};

function estadoEntidad(e: Fila): { clase: string; texto: string } {
  if (e.UltimoEstado === 'corriendo') return { clase: 'en-curso', texto: 'Sincronizando…' };
  if (e.UltimoEstado === 'error') return { clase: 'error', texto: 'Falló; se reintentará automáticamente' };
  if (e.UltimaOk) return { clase: 'ok', texto: `Listo · ${formatear(e.UltimaOk, 'datetimeoffset')}` };
  if (e.Modo === 'dependiente') return { clase: 'espera', texto: 'Se actualiza junto con los issues' };
  return { clase: 'espera', texto: 'Pendiente' };
}

interface Props {
  fuentes: Fila[];
  entidades: Fila[];
  error: string | null;
  onSolicitar: () => Promise<void>;
}

/** Se muestra hasta que todas las fuentes tienen datos vigentes: la aplicación sincroniza antes de hacer nada. */
export function PantallaSincronizacion({ fuentes, entidades, error, onSolicitar }: Props) {
  const [enviando, setEnviando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);

  const solicitar = async () => {
    setEnviando(true);
    setAviso(null);
    try {
      await onSolicitar();
      setAviso('Solicitud enviada. La sincronización empieza en menos de un minuto.');
    } catch {
      setAviso('No se pudo enviar la solicitud. Intente de nuevo.');
    } finally {
      setEnviando(false);
    }
  };

  return (
    <main className="pantalla-sync" aria-labelledby="titulo-sync">
      <div className="tarjeta">
        <div className="indicador" aria-hidden="true" />
        <h1 id="titulo-sync">Sincronizando los datos de Jira</h1>
        <p className="secundario">
          Antes de consultar, la aplicación trae de Jira los proyectos, tickets, tiempos y SLA más recientes.
          Esta pantalla se actualiza sola y se cierra en cuanto los datos estén listos.
        </p>
        {error && <p className="alerta" role="alert">{error}</p>}

        <div role="status" aria-live="polite">
          {fuentes.map((f) => (
            <section key={String(f.Fuente)} className="fuente">
              <h2>
                {String(f.Fuente)}{' '}
                <span className={f.DatosVigentes ? 'etiqueta ok' : 'etiqueta espera'}>
                  {f.DatosVigentes ? 'Datos al día' : 'En proceso'}
                </span>
              </h2>
              <ul className="entidades">
                {entidades
                  .filter((e) => e.Fuente === f.Fuente)
                  .map((e) => {
                    const s = estadoEntidad(e);
                    return (
                      <li key={String(e.Entidad)} className={s.clase}>
                        <span className="punto" aria-hidden="true" />
                        <span className="nombre">{NOMBRES[String(e.Entidad)] ?? String(e.Entidad)}</span>
                        <span className="detalle" title={e.UltimoEstado === 'error' ? String(e.UltimoMensaje ?? '') : undefined}>
                          {s.texto}
                        </span>
                      </li>
                    );
                  })}
              </ul>
              {Number(f.DocumentosEnCuarentena) > 0 && (
                <p className="secundario">{String(f.DocumentosEnCuarentena)} documento(s) con error quedaron apartados; el administrador puede revisarlos en Avisos.</p>
              )}
            </section>
          ))}
          {fuentes.length === 0 && !error && <p className="secundario">Consultando el estado…</p>}
        </div>

        <button type="button" className="boton" onClick={solicitar} disabled={enviando}>
          {enviando ? 'Enviando…' : 'Sincronizar ahora'}
        </button>
        {aviso && <p className="secundario" role="status">{aviso}</p>}
      </div>
    </main>
  );
}
