import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, ErrorApi } from '../api';
import { describirCriterio, type CampoBuscador, type Criterio, type TipoCampo } from '../buscador';
import { aCsv, esNumero, formatear } from '../formato';
import type { ConjuntoResultados, Fila, ValoresFormulario } from '../tipos';

interface Props {
  consultaId: number;
  onNavegar: (nombre: string | null, valores?: ValoresFormulario) => void;
  puedeVerDetalle: boolean;
  onSyncPendiente: () => void;
  onEliminada: () => void;
}

const TAMANO = 50;
const mensaje = (e: unknown, otro: string) => (e instanceof ErrorApi ? e.message : otro);

/**
 * Una consulta personalizada publicada por un administrador: muestra sus criterios (de solo lectura) y sus resultados con
 * orden y páginas. Los clientes externos ven solo los tickets de su organización (lo aplica SQL Server).
 */
export function ConsultaPersonalizadaVista({ consultaId, onNavegar, puedeVerDetalle, onSyncPendiente, onEliminada }: Props) {
  const [def, setDef] = useState<Fila | null>(null);
  const [campos, setCampos] = useState<CampoBuscador[]>([]);
  const [datos, setDatos] = useState<ConjuntoResultados | null>(null);
  const [orden, setOrden] = useState<{ campo: string; desc: boolean } | null>(null);
  const [pagina, setPagina] = useState(1);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const falla = useCallback((e: unknown, otro: string) => {
    if (e instanceof ErrorApi && e.sincronizacionPendiente) onSyncPendiente();
    setError(mensaje(e, otro));
  }, [onSyncPendiente]);

  useEffect(() => {
    api.ejecutar('ConsultaPersonalizada_Obtener', { ConsultaId: consultaId })
      .then((r) => {
        setDef(r.resultados[0]?.filas[0] ?? null);
        setCampos((r.resultados[1]?.filas ?? []).map((f) => ({
          clave: String(f.Clave), etiqueta: String(f.Etiqueta), tipo: String(f.Tipo) as TipoCampo, alias: String(f.Alias),
          multivalor: f.Multivalor === true, origen: '', esColumna: true, predeterminada: false, operadores: [],
        })));
      })
      .catch((e) => falla(e, 'No se pudo abrir la consulta.'));
  }, [consultaId, falla]);

  const cuerpo = (pag: number, tamano: number) => ({
    ConsultaId: consultaId, Pagina: pag, TamanoPagina: tamano,
    ...(orden ? { OrdenarPor: orden.campo, Descendente: orden.desc } : {}),
  });

  useEffect(() => {
    if (!def) return;
    let vigente = true;
    setCargando(true);
    api.ejecutar('ConsultaPersonalizada_Ejecutar', cuerpo(pagina, TAMANO))
      .then((r) => vigente && (setDatos(r.resultados[0] ?? null), setError(null)))
      .catch((e) => vigente && falla(e, 'No se pudo consultar.'))
      .finally(() => vigente && setCargando(false));
    return () => { vigente = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [def, pagina, orden]);

  const porAlias = useMemo(() => new Map(campos.map((c) => [c.alias, c])), [campos]);
  const criterios = useMemo<Criterio[]>(() => {
    try { return JSON.parse(String(def?.Criterios ?? '[]')) as Criterio[]; } catch { return []; }
  }, [def]);

  if (!def) {
    return (
      <section className="vista">
        {error ? <p className="alerta" role="alert">{error}</p> : <p role="status" className="secundario">Cargando…</p>}
      </section>
    );
  }

  const columnas = datos?.columnas.filter((c) => c.nombre !== 'TotalFilas') ?? [];
  const total = Number(datos?.filas[0]?.TotalFilas ?? 0);
  const paginas = Math.max(1, Math.ceil(total / TAMANO));
  const desde = total === 0 ? 0 : (pagina - 1) * TAMANO + 1;

  const ordenar = (alias: string) => {
    const c = porAlias.get(alias);
    if (!c || c.multivalor) return;
    setPagina(1);
    setOrden((o) => (o?.campo === c.clave ? { campo: c.clave, desc: !o.desc } : { campo: c.clave, desc: c.tipo === 'fecha' || c.tipo === 'numero' }));
  };

  const descargar = async () => {
    try {
      const r = await api.ejecutar('ConsultaPersonalizada_Ejecutar', cuerpo(1, 500));
      const c = r.resultados[0];
      if (!c) return;
      const url = URL.createObjectURL(new Blob([aCsv(c.columnas.filter((x) => x.nombre !== 'TotalFilas'), c.filas)], { type: 'text/csv;charset=utf-8' }));
      const a = document.createElement('a');
      a.href = url;
      a.download = `${String(def.Nombre)}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      falla(e, 'No se pudo descargar.');
    }
  };

  const editar = () => onNavegar('Issues_Consultar', {
    ConsultaId: String(consultaId), Criterios: String(def.Criterios ?? '[]'),
    ...(def.Columnas ? { Columnas: String(def.Columnas) } : {}),
    ...(def.OrdenarPor ? { OrdenarPor: String(def.OrdenarPor) } : {}),
    ...(def.Descendente === false ? { Descendente: 'false' } : {}),
  });

  const eliminar = async () => {
    if (!window.confirm(`¿Eliminar la consulta «${String(def.Nombre)}»? Quienes la tienen compartida dejarán de verla.`)) return;
    try {
      await api.ejecutar('ConsultaPersonalizada_Eliminar', { ConsultaId: consultaId });
      onEliminada();
    } catch (e) {
      falla(e, 'No se pudo eliminar.');
    }
  };

  const etiquetaDe = (clave: string) => campos.find((c) => c.clave === clave);

  return (
    <section className="vista consulta-personalizada">
      <header>
        <h1>{String(def.Nombre)}</h1>
        {def.Descripcion ? <p className="secundario">{String(def.Descripcion)}</p> : null}
      </header>
      {criterios.length > 0 && (
        <ul className="chips" aria-label="Criterios de la consulta">
          {criterios.map((c, i) => <li key={i} className="chip activo">{describirCriterio(c, etiquetaDe(c.campo))}</li>)}
        </ul>
      )}
      {def.SoloMiOrganizacion === true && <p className="secundario">Se muestran solo los tickets de su organización.</p>}
      {def.PuedoEditar === true && (
        <p className="secundario">
          Compartida con: {def.CompartidaCon ? String(def.CompartidaCon) : 'nadie (solo administradores)'}
        </p>
      )}

      <div className="herramientas-resultado">
        <span className="secundario" role="status" aria-live="polite">
          {cargando ? 'Buscando…' : total === 0 ? 'Sin resultados' : `${desde.toLocaleString('es-MX')}–${Math.min(total, pagina * TAMANO).toLocaleString('es-MX')} de ${total.toLocaleString('es-MX')} issues`}
        </span>
        <div className="acciones">
          {total > 0 && <button type="button" className="boton secundario-btn" onClick={() => void descargar()} title="Hasta 500 issues">Descargar CSV</button>}
          {def.PuedoEditar === true && (
            <>
              <button type="button" className="boton secundario-btn" onClick={editar}>Editar en búsqueda avanzada</button>
              <button type="button" className="boton secundario-btn peligro" onClick={() => void eliminar()}>Eliminar</button>
            </>
          )}
        </div>
      </div>
      {error && <p className="alerta" role="alert">{error}</p>}

      {datos && datos.filas.length === 0 && !cargando && <p className="vacio">No hay issues con estos criterios.</p>}
      {datos && datos.filas.length > 0 && (
        <div className={`contenedor-tabla${cargando ? ' cargando' : ''}`}>
          <table>
            <thead>
              <tr>
                {columnas.map((c) => {
                  const campo = porAlias.get(c.nombre);
                  const activa = campo && orden?.campo === campo.clave;
                  return (
                    <th key={c.nombre} scope="col" className={esNumero(c.tipo) ? 'num' : undefined}
                        aria-sort={activa ? (orden!.desc ? 'descending' : 'ascending') : undefined}>
                      {campo && !campo.multivalor ? (
                        <button type="button" onClick={() => ordenar(c.nombre)}>
                          {campo.etiqueta}<span aria-hidden="true">{activa ? (orden!.desc ? ' ▼' : ' ▲') : ''}</span>
                        </button>
                      ) : (campo?.etiqueta ?? c.nombre)}
                    </th>
                  );
                })}
              </tr>
            </thead>
            <tbody>
              {datos.filas.map((f) => (
                <tr key={String(f.Clave)}>
                  {columnas.map((c) => {
                    const v = f[c.nombre];
                    const t = formatear(v, c.tipo);
                    return (
                      <td key={c.nombre} className={esNumero(c.tipo) ? 'num' : undefined}>
                        {c.nombre === 'Clave' && puedeVerDetalle && typeof v === 'string'
                          ? <button type="button" className="enlace" onClick={() => onNavegar('Issue_Detalle', { Clave: v })}>{v}</button>
                          : t.length > 120 ? <span title={t}>{t.slice(0, 117)}…</span> : t}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {paginas > 1 && (
        <nav className="paginacion" aria-label="Páginas">
          <button type="button" className="boton secundario-btn" disabled={pagina <= 1} onClick={() => setPagina((p) => p - 1)}>← Anterior</button>
          <span>Página {pagina} de {paginas}</span>
          <button type="button" className="boton secundario-btn" disabled={pagina >= paginas} onClick={() => setPagina((p) => p + 1)}>Siguiente →</button>
        </nav>
      )}
    </section>
  );
}
