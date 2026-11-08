import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, ErrorApi } from './api';
import { etiquetasDeValores, formatear } from './formato';
import { useSincronizacion } from './sincronizacion';
import type { ProcedimientoInfo, ValoresFormulario } from './tipos';
import { Inicio } from './componentes/Inicio';
import { PantallaSincronizacion } from './componentes/PantallaSincronizacion';
import { VistaProcedimiento } from './componentes/VistaProcedimiento';

interface Seleccion {
  nombre: string | null;
  valores: ValoresFormulario;
}

/** La dirección guarda lo que se está viendo: ?p=Issues_Buscar&Proyecto=SMC26 */
function leerUrl(): Seleccion {
  const q = new URLSearchParams(window.location.search);
  const nombre = q.get('p');
  q.delete('p');
  return { nombre, valores: Object.fromEntries(q.entries()) };
}

function escribirUrl(s: Seleccion, reemplazar: boolean) {
  const q = new URLSearchParams(s.valores);
  if (s.nombre) q.set('p', s.nombre);
  const url = `${window.location.pathname}${q.size ? `?${q}` : ''}`;
  if (url === `${window.location.pathname}${window.location.search}`) return;
  if (reemplazar) window.history.replaceState(null, '', url);
  else window.history.pushState(null, '', url);
}

interface PropsApp {
  intervaloSyncMs?: number;
}

export default function App({ intervaloSyncMs }: PropsApp = {}) {
  const sync = useSincronizacion(intervaloSyncMs, intervaloSyncMs);
  const [procs, setProcs] = useState<ProcedimientoInfo[] | null>(null);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const [seleccion, setSeleccion] = useState<Seleccion>(leerUrl);
  const [vista, setVista] = useState(0); // fuerza a recrear la vista al navegar

  useEffect(() => {
    api.listar().then(setProcs).catch((e) => setErrorCarga(e instanceof ErrorApi ? e.message : 'No se pudo cargar la aplicación.'));
  }, []);

  useEffect(() => {
    const alVolver = () => {
      setSeleccion(leerUrl());
      setVista((v) => v + 1);
    };
    window.addEventListener('popstate', alVolver);
    return () => window.removeEventListener('popstate', alVolver);
  }, []);

  const navegar = useCallback((nombre: string | null, valores: ValoresFormulario = {}, reemplazar = false) => {
    const s = { nombre, valores };
    escribirUrl(s, reemplazar);
    if (!reemplazar) {
      setSeleccion(s);
      setVista((v) => v + 1);
    }
  }, []);

  const grupos = useMemo(() => {
    const lista = [...(procs ?? [])].sort((a, b) => a.titulo.localeCompare(b.titulo, 'es'));
    return [
      { titulo: 'Consultas', procs: lista.filter((p) => p.permiso === 'lectura' && !p.exentoSync) },
      { titulo: 'Sincronización', procs: lista.filter((p) => p.permiso === 'lectura' && p.exentoSync) },
      { titulo: 'Administración', procs: lista.filter((p) => p.permiso !== 'lectura') },
    ].filter((g) => g.procs.length > 0);
  }, [procs]);

  const etiquetasValores = useMemo(() => etiquetasDeValores(procs ?? []), [procs]);

  if (errorCarga) {
    return <main className="pantalla-sync"><div className="tarjeta"><h1>No se pudo abrir SMCClient</h1><p className="alerta" role="alert">{errorCarga}</p></div></main>;
  }
  if (sync.listo === null || procs === null) {
    return <main className="pantalla-sync"><div className="tarjeta"><div className="indicador" aria-hidden="true" /><p role="status">Cargando…</p></div></main>;
  }
  if (!sync.listo) {
    return <PantallaSincronizacion fuentes={sync.fuentes} entidades={sync.entidades} error={sync.error} onSolicitar={sync.solicitar} />;
  }

  const proc = procs.find((p) => p.nombre.toLowerCase() === seleccion.nombre?.toLowerCase()) ?? null;
  const ultima = sync.fuentes.map((f) => f.UltimaSincronizacion).filter((x): x is string => typeof x === 'string').sort()[0];
  const avisos = sync.fuentes.reduce((n, f) => n + Number(f.AvisosAbiertos ?? 0), 0);
  const verAvisos = procs.some((p) => p.nombre === 'Avisos_Listar');

  return (
    <div className="app">
      <header className="barra">
        <a className="marca" href="./" onClick={(e) => { e.preventDefault(); navegar(null); }}>
          SMCClient <span>Scrum y mesa de ayuda</span>
        </a>
        <div className="estado-sync">
          {ultima && <span title="Fecha de la sincronización más antigua entre los datos">Datos de Jira al {formatear(ultima, 'datetimeoffset')}</span>}
          {avisos > 0 && verAvisos && (
            <button type="button" className="insignia" onClick={() => navegar('Avisos_Listar')}>{avisos} aviso(s)</button>
          )}
          <button type="button" className="boton secundario-btn" onClick={() => void sync.solicitar()}>Sincronizar ahora</button>
        </div>
      </header>
      <nav className="menu" aria-label="Consultas">
        {grupos.map((g) => (
          <section key={g.titulo}>
            <h2>{g.titulo}</h2>
            <ul>
              {g.procs.map((p) => (
                <li key={p.nombre}>
                  <a
                    href={`?p=${encodeURIComponent(p.nombre)}`}
                    aria-current={proc?.nombre === p.nombre ? 'page' : undefined}
                    title={p.descripcion ?? undefined}
                    onClick={(e) => { e.preventDefault(); navegar(p.nombre); }}
                  >
                    {p.titulo}
                  </a>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </nav>
      <main className="contenido">
        {proc ? (
          <VistaProcedimiento
            key={`${proc.nombre}-${vista}`}
            proc={proc}
            valoresUrl={seleccion.valores}
            onNavegar={navegar}
            puedeVerDetalle={procs.some((p) => p.nombre === 'Issue_Detalle')}
            onSyncPendiente={sync.marcarPendiente}
            etiquetasValores={etiquetasValores}
          />
        ) : (
          <Inicio consultas={grupos.find((g) => g.titulo === 'Consultas')?.procs ?? []} onAbrir={(n) => navegar(n)} />
        )}
      </main>
    </div>
  );
}
