import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, ErrorApi } from '../api';
import { formatear } from '../formato';
import type { Fila } from '../tipos';

const TIPOS: Record<string, string> = { software: 'Scrum', service_desk: 'Mesa de ayuda', business: 'Negocio' };
const n = (v: unknown) => Number(v ?? 0).toLocaleString('es-MX');

/**
 * "Proyectos a sincronizar": una casilla por proyecto de Jira. Desactivado = no se pide a Jira y sus datos se ocultan de
 * los reportes (no se borran); al reactivarlo se vuelven a pedir sus issues. También decide qué pasa con los proyectos
 * nuevos que aparezcan en Jira.
 */
export function ProyectosSync() {
  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [nuevos, setNuevos] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [texto, setTexto] = useState('');
  const [tipo, setTipo] = useState('');
  const [estado, setEstado] = useState<'' | 'si' | 'no'>('');

  const aplicar = (r: { resultados: { filas: Fila[] }[] }) => {
    setFilas(r.resultados[0]?.filas ?? []);
    const conf = r.resultados[1]?.filas[0];
    if (conf) setNuevos(conf.NuevosSeSincronizan === true);
  };
  const cargar = useCallback(() => {
    api.ejecutar('ProyectosSync_Listar').then(aplicar)
      .catch((e) => setError(e instanceof ErrorApi ? e.message : 'No se pudo cargar la lista de proyectos.'));
  }, []);
  useEffect(cargar, [cargar]);

  const cambiar = async (f: Fila, sincronizar: boolean) => {
    const clave = String(f.Clave);
    if (!sincronizar && !window.confirm(
      `¿Dejar de sincronizar ${clave}?\n\nNo se pedirá a Jira y sus ${n(f.Issues)} issues se ocultarán de los reportes. ` +
      'Los datos no se borran: si lo vuelve a activar, se traerán de nuevo.')) return;
    setOcupado(clave); setError(null); setAviso(null);
    try {
      const r = await api.ejecutar('ProyectoSync_Establecer', { Fuente: f.Fuente, Proyecto: clave, Sincronizar: sincronizar });
      setFilas(r.resultados[0]?.filas ?? []);
      setAviso(sincronizar
        ? `${clave} se volverá a sincronizar: sus issues se piden a Jira en la próxima vuelta del sincronizador (menos de un minuto).`
        : `${clave} ya no se sincroniza y se ocultó de los reportes.`);
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo guardar el cambio.');
    } finally {
      setOcupado(null);
    }
  };

  const cambiarNuevos = async (valor: boolean) => {
    setOcupado('_nuevos'); setError(null);
    try {
      const r = await api.ejecutar('ProyectosSync_Nuevos_Guardar', { Sincronizar: valor });
      setNuevos(r.resultados[0]?.filas[0]?.NuevosSeSincronizan === true);
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudo guardar el cambio.');
    } finally {
      setOcupado(null);
    }
  };

  const visibles = useMemo(() => {
    const t = texto.trim().toLocaleLowerCase('es-MX');
    return (filas ?? []).filter((f) =>
      (!t || `${String(f.Clave)} ${String(f.Nombre ?? '')}`.toLocaleLowerCase('es-MX').includes(t))
      && (!tipo || f.TipoProyecto === tipo)
      && (!estado || (f.Sincronizar === true) === (estado === 'si')));
  }, [filas, texto, tipo, estado]);

  const activos = (filas ?? []).filter((f) => f.Sincronizar === true);

  return (
    <article className="vista">
      <header>
        <h1>Proyectos a sincronizar</h1>
        <p className="secundario">
          Marque los proyectos de Jira que se usan en los reportes. Un proyecto desmarcado no se pide a Jira y sus datos se
          ocultan de todas las consultas (no se borran: al volver a marcarlo se traen de nuevo).
        </p>
      </header>

      {error && <p className="alerta" role="alert">{error}</p>}
      {aviso && <p className="aviso" role="status">{aviso}</p>}

      {nuevos !== null && (
        <label className="casilla opcion-nuevos">
          <input type="checkbox" checked={nuevos} disabled={ocupado === '_nuevos'} onChange={(e) => void cambiarNuevos(e.target.checked)} />
          <span>
            <strong>Sincronizar automáticamente los proyectos nuevos de Jira</strong>
            <small className="secundario"> — si se desmarca, un proyecto nuevo queda desactivado hasta que lo marque aquí.</small>
          </span>
        </label>
      )}

      {filas === null && !error && <p role="status">Cargando proyectos…</p>}
      {filas && (
        <>
          <div className="filtros-proyectos">
            <label>Buscar <input type="search" value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Clave o nombre" /></label>
            <label>Tipo
              <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
                <option value="">Todos</option>
                {Object.entries(TIPOS).map(([v, e]) => <option key={v} value={v}>{e}</option>)}
              </select>
            </label>
            <label>Mostrar
              <select value={estado} onChange={(e) => setEstado(e.target.value as '' | 'si' | 'no')}>
                <option value="">Todos</option>
                <option value="si">Se sincronizan</option>
                <option value="no">Desactivados</option>
              </select>
            </label>
            <p className="secundario resumen-proyectos" role="status">
              {activos.length} de {filas.length} proyectos se sincronizan · {n(activos.reduce((s, f) => s + Number(f.Issues ?? 0), 0))} issues en reportes
            </p>
          </div>
          <div className="contenedor-tabla">
            <table>
              <thead>
                <tr>
                  <th scope="col">Sincronizar</th>
                  <th scope="col">Proyecto</th>
                  <th scope="col">Tipo</th>
                  <th scope="col" className="num">Issues</th>
                  <th scope="col" className="num">Abiertos</th>
                  <th scope="col">Última actividad</th>
                  <th scope="col">Nota</th>
                </tr>
              </thead>
              <tbody>
                {visibles.map((f) => {
                  const clave = String(f.Clave);
                  const activo = f.Sincronizar === true;
                  return (
                    <tr key={`${String(f.Fuente)}-${clave}`} className={activo ? undefined : 'fila-inactiva'}>
                      <td>
                        <input type="checkbox" checked={activo} disabled={ocupado === clave}
                               aria-label={`Sincronizar ${clave}`} onChange={(e) => void cambiar(f, e.target.checked)} />
                      </td>
                      <td><strong>{clave}</strong> <span className="secundario">{String(f.Nombre ?? '')}</span></td>
                      <td>{TIPOS[String(f.TipoProyecto)] ?? String(f.TipoProyecto ?? '—')}</td>
                      <td className="num">{n(f.Issues)}</td>
                      <td className="num">{n(f.Abiertos)}</td>
                      <td>{formatear(f.UltimaActualizacion, 'datetimeoffset')}</td>
                      <td className="secundario">{activo ? '' : `${String(f.Motivo ?? 'Desactivado')}${f.DesactivadoEl ? ` (${formatear(f.DesactivadoEl, 'datetimeoffset')})` : ''}`}</td>
                    </tr>
                  );
                })}
                {visibles.length === 0 && <tr><td colSpan={7} className="vacio">Ningún proyecto coincide con los filtros.</td></tr>}
              </tbody>
            </table>
          </div>
        </>
      )}
    </article>
  );
}
