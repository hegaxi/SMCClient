import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, ErrorApi } from './api';
import { etiquetasDeValores, formatear } from './formato';
import { useSincronizacion } from './sincronizacion';
import type { ProcedimientoInfo, Sesion, ValoresFormulario } from './tipos';
import { CambiarContrasena } from './componentes/CambiarContrasena';
import { Inicio } from './componentes/Inicio';
import { PantallaSincronizacion } from './componentes/PantallaSincronizacion';
import { RestablecerContrasena } from './componentes/RestablecerContrasena';
import { VistaProcedimiento } from './componentes/VistaProcedimiento';

/** Vistas propias de la interfaz (no son procedimientos). */
const VISTA_CONTRASENA = '_contrasena';
const VISTA_RESTABLECER = '_restablecer';

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

interface Props {
  sesion: Sesion;
  intervaloSyncMs?: number;
  onSalir: () => void;
}

export function Principal({ sesion, intervaloSyncMs, onSalir }: Props) {
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
    const lista = [...(procs ?? [])].filter((p) => p.permiso !== 'usuario').sort((a, b) => a.titulo.localeCompare(b.titulo, 'es'));
    return [
      { titulo: 'Consultas', procs: lista.filter((p) => p.permiso === 'lectura' && !p.exentoSync) },
      { titulo: 'Sincronización', procs: lista.filter((p) => p.permiso === 'lectura' && p.exentoSync) },
      { titulo: 'Administración', procs: lista.filter((p) => p.permiso !== 'lectura') },
    ].filter((g) => g.procs.length > 0);
  }, [procs]);

  const etiquetasValores = useMemo(() => etiquetasDeValores(procs ?? []), [procs]);

  const barra = (
    <header className="barra">
      <a className="marca" href="./" onClick={(e) => { e.preventDefault(); navegar(null); }}>
        SMCClient <span>Scrum y mesa de ayuda</span>
      </a>
      <div className="estado-sync">
        <span className="usuario" title={sesion.roles ?? undefined}>{sesion.nombre}</span>
        <button type="button" className="enlace" onClick={() => navegar(VISTA_CONTRASENA)}>Cambiar contraseña</button>
        <button type="button" className="boton secundario-btn" onClick={onSalir}>Salir</button>
      </div>
    </header>
  );

  if (errorCarga) {
    return (
      <main className="pantalla-sync"><div className="tarjeta">
        <h1>No se pudo abrir SMCClient</h1><p className="alerta" role="alert">{errorCarga}</p>
        <button type="button" className="boton secundario-btn" onClick={onSalir}>Salir</button>
      </div></main>
    );
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

  let contenido;
  if (seleccion.nombre === VISTA_CONTRASENA) contenido = <CambiarContrasena obligatorio={false} onListo={() => navegar(null)} onCancelar={() => navegar(null)} />;
  else if (seleccion.nombre === VISTA_RESTABLECER && sesion.esAdministrador) contenido = <RestablecerContrasena />;
  else if (proc)
    contenido = (
      <VistaProcedimiento
        key={`${proc.nombre}-${vista}`}
        proc={proc}
        valoresUrl={seleccion.valores}
        onNavegar={navegar}
        puedeVerDetalle={procs.some((p) => p.nombre === 'Issue_Detalle')}
        onSyncPendiente={sync.marcarPendiente}
        etiquetasValores={etiquetasValores}
      />
    );
  else contenido = <Inicio consultas={grupos.find((g) => g.titulo === 'Consultas')?.procs ?? []} onAbrir={(n) => navegar(n)} />;

  const enlace = (nombre: string, titulo: string, descripcion?: string | null) => (
    <li key={nombre}>
      <a href={`?p=${encodeURIComponent(nombre)}`} aria-current={seleccion.nombre === nombre ? 'page' : undefined} title={descripcion ?? undefined}
         onClick={(e) => { e.preventDefault(); navegar(nombre); }}>
        {titulo}
      </a>
    </li>
  );

  return (
    <div className="app">
      {barra}
      <nav className="menu" aria-label="Consultas">
        <p className="datos-al secundario">
          {ultima && <>Datos de Jira al {formatear(ultima, 'datetimeoffset')}</>}
          {avisos > 0 && verAvisos && (
            <button type="button" className="insignia" onClick={() => navegar('Avisos_Listar')}>{avisos} aviso(s)</button>
          )}
        </p>
        {grupos.map((g) => (
          <section key={g.titulo}>
            <h2>{g.titulo}</h2>
            <ul>
              {g.procs.map((p) => enlace(p.nombre, p.titulo, p.descripcion))}
              {g.titulo === 'Administración' && sesion.esAdministrador && enlace(VISTA_RESTABLECER, 'Restablecer contraseña', 'Asigna una contraseña temporal a un usuario.')}
            </ul>
          </section>
        ))}
        <button type="button" className="boton secundario-btn sync-menu" onClick={() => void sync.solicitar()}>Sincronizar ahora</button>
      </nav>
      <main className="contenido">{contenido}</main>
    </div>
  );
}
