import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, ErrorApi } from './api';
import { etiquetasDeValores, formatear } from './formato';
import { useSincronizacion } from './sincronizacion';
import type { Fila, ProcedimientoInfo, Sesion, ValoresFormulario } from './tipos';
import { BuscadorIssues } from './componentes/BuscadorIssues';
import { CambiarContrasena } from './componentes/CambiarContrasena';
import { EditorTablero } from './componentes/EditorTablero';
import { MisFiltros } from './componentes/MisFiltros';
import { TableroVista } from './componentes/TableroVista';
import { Inicio } from './componentes/Inicio';
import { PantallaSincronizacion } from './componentes/PantallaSincronizacion';
import { RestablecerContrasena } from './componentes/RestablecerContrasena';
import { VistaProcedimiento } from './componentes/VistaProcedimiento';

/** Vistas propias de la interfaz (no son procedimientos). */
const VISTA_CONTRASENA = '_contrasena';
const VISTA_RESTABLECER = '_restablecer';
const VISTA_TABLERO = '_tablero';
const VISTA_TABLERO_NUEVO = '_tablero_nuevo';
const VISTA_TABLERO_EDITAR = '_tablero_editar';
const VISTA_FILTROS = '_filtros';

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

  const [tableros, setTableros] = useState<Fila[]>([]);

  useEffect(() => {
    api.listar().then(setProcs).catch((e) => setErrorCarga(e instanceof ErrorApi ? e.message : 'No se pudo cargar la aplicación.'));
  }, []);

  const tienenTableros = procs?.some((p) => p.nombre === 'Tableros_Listar') ?? false;
  const cargarTableros = useCallback(() => {
    if (tienenTableros) api.ejecutar('Tableros_Listar').then((r) => setTableros(r.resultados[0]?.filas ?? [])).catch(() => setTableros([]));
  }, [tienenTableros]);
  useEffect(() => { cargarTableros(); }, [cargarTableros]);

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
    const lista = [...(procs ?? [])].filter((p) => p.permiso !== 'usuario' && !p.oculto).sort((a, b) => a.titulo.localeCompare(b.titulo, 'es'));
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
  // Después de la primera carga la aplicación no se bloquea si Jira o el worker fallan: se avisa del atraso.
  const atrasadas = sync.fuentes.filter((f) => f.DatosAtrasados === true);
  const minutosAtraso = Math.max(0, ...atrasadas.map((f) => Number(f.MinutosDesdeSincronizacion ?? 0)));
  const verAvisos = procs.some((p) => p.nombre === 'Avisos_Listar');

  const tableroInicio = tableros.find((t) => t.EsInicio === true);
  const abrirTablero = (id: unknown) => navegar(VISTA_TABLERO, { t: String(id) });
  const tableroVista = (id: number) => (
    <TableroVista key={`${id}-${vista}`} tableroId={id} procs={procs} etiquetasValores={etiquetasValores}
                  onAbrirConsulta={(n, v) => navegar(n, v)}
                  onEditarTablero={(t) => navegar(VISTA_TABLERO_EDITAR, { t: String(t.TableroId) })}
                  onEliminado={() => { cargarTableros(); navegar(null); }}
                  onCambio={cargarTableros}
                  onSyncPendiente={sync.marcarPendiente} />
  );

  let contenido;
  if (seleccion.nombre === VISTA_TABLERO && seleccion.valores.t) contenido = tableroVista(Number(seleccion.valores.t));
  else if (seleccion.nombre === VISTA_TABLERO_NUEVO || seleccion.nombre === VISTA_TABLERO_EDITAR)
    contenido = (
      <EditorTablero key={`${seleccion.nombre}-${vista}`} tablero={tableros.find((t) => String(t.TableroId) === seleccion.valores.t)}
                     onGuardado={(id) => { cargarTableros(); abrirTablero(id); }} onCancelar={() => window.history.back()} />
    );
  else if (seleccion.nombre === VISTA_FILTROS) contenido = <MisFiltros onAbrir={(n, v) => navegar(n, v)} />;
  else if (seleccion.nombre === VISTA_CONTRASENA) contenido = <CambiarContrasena obligatorio={false} onListo={() => navegar(null)} onCancelar={() => navegar(null)} />;
  else if (seleccion.nombre === VISTA_RESTABLECER && sesion.esAdministrador) contenido = <RestablecerContrasena />;
  else if (proc?.nombre === 'Issues_Consultar')
    contenido = (
      <BuscadorIssues key={`${proc.nombre}-${vista}`} proc={proc} valoresUrl={seleccion.valores} onNavegar={navegar}
                      puedeVerDetalle={procs.some((p) => p.nombre === 'Issue_Detalle')}
                      puedeGuardarFiltro={procs.some((p) => p.nombre === 'Filtro_Guardar')}
                      onSyncPendiente={sync.marcarPendiente} />
    );
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
        puedeGuardarFiltro={procs.some((p) => p.nombre === 'Filtro_Guardar')}
      />
    );
  else if (tableroInicio) contenido = tableroVista(Number(tableroInicio.TableroId));
  else contenido = <Inicio consultas={grupos.find((g) => g.titulo === 'Consultas')?.procs ?? []} onAbrir={(n) => navegar(n)} />;

  const enlace = (nombre: string, titulo: string, descripcion?: string | null, valores: ValoresFormulario = {}) => {
    const actual = seleccion.nombre === nombre && Object.entries(valores).every(([k, v]) => seleccion.valores[k] === v);
    const q = new URLSearchParams({ ...valores, p: nombre });
    return (
      <li key={`${nombre}-${JSON.stringify(valores)}`}>
        <a href={`?${q}`} aria-current={actual ? 'page' : undefined} title={descripcion ?? undefined}
           onClick={(e) => { e.preventDefault(); navegar(nombre, valores); }}>
          {titulo}
        </a>
      </li>
    );
  };

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
        {tienenTableros && (
          <section>
            <h2>Tableros</h2>
            <ul>
              {tableros.map((t) => enlace(VISTA_TABLERO, `${String(t.Nombre)}${t.EsInicio ? ' ★' : ''}`,
                t.EsMio ? String(t.Descripcion ?? '') : `De ${String(t.Propietario)}`, { t: String(t.TableroId) }))}
              {enlace(VISTA_TABLERO_NUEVO, '+ Nuevo tablero')}
              {enlace(VISTA_FILTROS, 'Mis filtros')}
            </ul>
          </section>
        )}
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
      <main className="contenido">
        {atrasadas.length > 0 && (
          <p className="aviso-atraso" role="status">
            Los datos de Jira tienen {textoAtraso(minutosAtraso)} sin actualizarse: la sincronización está fallando o detenida.
            Puede seguir consultando; lo más reciente de Jira todavía no aparece.
            {verAvisos && <> <button type="button" className="enlace" onClick={() => navegar('Avisos_Listar')}>Ver avisos</button></>}
          </p>
        )}
        {contenido}
      </main>
    </div>
  );
}

/** 45 -> "45 minutos"; 130 -> "2 horas"; 3000 -> "2 días". */
export function textoAtraso(minutos: number): string {
  if (minutos < 120) return `${minutos} minutos`;
  if (minutos < 48 * 60) return `${Math.floor(minutos / 60)} horas`;
  return `${Math.floor(minutos / 1440)} días`;
}
