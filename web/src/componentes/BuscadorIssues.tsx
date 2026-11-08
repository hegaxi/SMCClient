import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { api, ErrorApi } from '../api';
import {
  aParametros, CAMPOS_BASICOS, columnasEfectivas, criterioCompleto, deParametros, describirCriterio, leerCampos, moverColumna,
  OPERADORES, operadorInicial, sinValor, TAMANO_PAGINA, usaLista, type CampoBuscador, type Criterio, type EstadoBusqueda,
} from '../buscador';
import { aCsv, esNumero, formatear } from '../formato';
import type { ConjuntoResultados, ProcedimientoInfo, ValoresFormulario } from '../tipos';
import { FECHAS_RELATIVAS, GuardarFiltro } from './GuardarFiltro';

interface Props {
  proc: ProcedimientoInfo;
  valoresUrl: ValoresFormulario;
  onNavegar: (nombre: string | null, valores?: ValoresFormulario, reemplazar?: boolean) => void;
  puedeVerDetalle: boolean;
  puedeGuardarFiltro: boolean;
  onSyncPendiente: () => void;
}

type Panel = 'campos' | 'columnas' | 'guardar' | null;
interface Edicion { indice: number | null; borrador: Criterio }

const mensaje = (e: unknown, otro: string) => (e instanceof ErrorApi ? e.message : otro);

/**
 * Búsqueda avanzada al estilo del navegador de issues de Jira: texto libre, criterios sobre cualquier campo (también los
 * personalizados), columnas a elegir y ordenar, orden y paginación en el servidor. Todo vive en la dirección, así que
 * se puede compartir el enlace o guardarlo como filtro para un tablero.
 */
export function BuscadorIssues({ proc, valoresUrl, onNavegar, puedeVerDetalle, puedeGuardarFiltro, onSyncPendiente }: Props) {
  const [campos, setCampos] = useState<CampoBuscador[] | null>(null);
  const [estado, setEstado] = useState<EstadoBusqueda>(() => deParametros(valoresUrl));
  const [resultado, setResultado] = useState<ConjuntoResultados | null>(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [edicion, setEdicion] = useState<Edicion | null>(null);
  const [panel, setPanel] = useState<Panel>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const indiceTexto = estado.criterios.findIndex((c) => c.campo === 'texto' && c.operador === 'contiene');
  const [texto, setTexto] = useState(indiceTexto >= 0 ? estado.criterios[indiceTexto].valor ?? '' : '');
  const consulta = useRef(0);

  useEffect(() => {
    api.ejecutar('Issues_Campos')
      .then((r) => setCampos(leerCampos(r.resultados[0]?.filas ?? [])))
      .catch((e) => {
        if (e instanceof ErrorApi && e.sincronizacionPendiente) onSyncPendiente();
        setError(mensaje(e, 'No se pudieron cargar los campos.'));
      });
  }, [onSyncPendiente]);

  const porClave = useMemo(() => new Map((campos ?? []).map((c) => [c.clave, c])), [campos]);
  const porAlias = useMemo(() => new Map((campos ?? []).map((c) => [c.alias, c])), [campos]);

  // Cada cambio: la dirección se actualiza (sin agregar historial) y se vuelve a consultar.
  useEffect(() => {
    if (!campos) return;
    const p = aParametros(estado, campos);
    onNavegar(proc.nombre, p, true);
    const n = ++consulta.current;
    setCargando(true);
    setError(null);
    api.ejecutar(proc.nombre, cuerpo(p, estado.pagina, TAMANO_PAGINA))
      .then((r) => n === consulta.current && setResultado(r.resultados[0] ?? null))
      .catch((e) => {
        if (n !== consulta.current) return;
        if (e instanceof ErrorApi && e.sincronizacionPendiente) onSyncPendiente();
        setError(mensaje(e, 'No se pudo consultar.'));
        setResultado(null);
      })
      .finally(() => n === consulta.current && setCargando(false));
  }, [campos, estado, proc.nombre, onNavegar, onSyncPendiente]);

  const cambiar = (c: Partial<EstadoBusqueda>) => setEstado((e) => ({ ...e, pagina: 1, ...c }));

  const aplicar = (ed: Edicion) => {
    const criterios = [...estado.criterios];
    if (ed.indice === null) criterios.push(ed.borrador);
    else criterios[ed.indice] = ed.borrador;
    cambiar({ criterios });
    setEdicion(null);
  };
  const quitar = (indice: number | null) => {
    if (indice !== null) cambiar({ criterios: estado.criterios.filter((_, i) => i !== indice) });
    setEdicion(null);
  };
  const abrir = (campo: CampoBuscador, indice: number) => {
    setPanel(null);
    setEdicion({ indice: indice >= 0 ? indice : null, borrador: indice >= 0 ? estado.criterios[indice] : { campo: campo.clave, operador: operadorInicial(campo) } });
  };

  const buscarTexto = (e: FormEvent) => {
    e.preventDefault();
    const otros = estado.criterios.filter((_, i) => i !== indiceTexto);
    cambiar({ criterios: texto.trim() ? [{ campo: 'texto', operador: 'contiene', valor: texto.trim() }, ...otros] : otros });
  };

  const ordenarPor = (columna: string) => {
    const campo = porAlias.get(columna);
    if (!campo || campo.multivalor) return;
    if (estado.ordenarPor === campo.clave) cambiar({ descendente: !estado.descendente });
    else cambiar({ ordenarPor: campo.clave, descendente: campo.tipo === 'fecha' || campo.tipo === 'numero' });
  };

  const descargar = async () => {
    try {
      const r = await api.ejecutar(proc.nombre, cuerpo(aParametros(estado, campos ?? []), 1, 500));
      const c = r.resultados[0];
      if (!c) return;
      const columnas = c.columnas.filter((x) => x.nombre !== 'TotalFilas');
      const url = URL.createObjectURL(new Blob([aCsv(columnas, c.filas)], { type: 'text/csv;charset=utf-8' }));
      const a = document.createElement('a');
      a.href = url;
      a.download = 'busqueda.csv';
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(mensaje(e, 'No se pudo descargar.'));
    }
  };

  if (!campos) {
    return (
      <section className="vista buscador">
        <header><h1>{proc.titulo}</h1></header>
        {error ? <p className="alerta" role="alert">{error}</p> : <p role="status" className="secundario">Cargando campos…</p>}
      </section>
    );
  }

  const basicos = CAMPOS_BASICOS.map((c) => porClave.get(c)).filter((c): c is CampoBuscador => !!c);
  const indicesBasicos = new Set(basicos.map((b) => estado.criterios.findIndex((c) => c.campo === b.clave)).filter((i) => i >= 0));
  const otros = estado.criterios.map((c, i) => ({ c, i })).filter(({ i }) => i !== indiceTexto && !indicesBasicos.has(i));
  const total = Number(resultado?.filas[0]?.TotalFilas ?? 0);
  const desde = total === 0 ? 0 : (estado.pagina - 1) * TAMANO_PAGINA + 1;
  const hasta = Math.min(total, estado.pagina * TAMANO_PAGINA);
  const paginas = Math.max(1, Math.ceil(total / TAMANO_PAGINA));
  const columnas = resultado?.columnas.filter((c) => c.nombre !== 'TotalFilas') ?? [];

  const chip = (campo: CampoBuscador, indice: number, key: string) => {
    const c = indice >= 0 ? estado.criterios[indice] : null;
    const abierto = edicion !== null && (edicion.indice === (indice >= 0 ? indice : null)) && edicion.borrador.campo === campo.clave;
    return (
      <button key={key} type="button" className={`chip${c && criterioCompleto(c, campo) ? ' activo' : ''}`} aria-expanded={abierto}
              onClick={() => (abierto ? setEdicion(null) : abrir(campo, indice))}>
        {c ? describirCriterio(c, campo) : `${campo.etiqueta}: todos`} <span aria-hidden="true">▾</span>
      </button>
    );
  };

  return (
    <section className="vista buscador">
      <header>
        <h1>{proc.titulo}</h1>
        {proc.descripcion && <p className="secundario">{proc.descripcion}</p>}
      </header>

      <div className="barra-busqueda">
        <form role="search" onSubmit={buscarTexto} className="texto-libre">
          <label htmlFor="bq-texto" className="solo-lectores">Buscar texto</label>
          <input id="bq-texto" type="search" placeholder="Buscar en clave o resumen…" value={texto} onChange={(e) => setTexto(e.target.value)} />
          <button type="submit" className="boton">Buscar</button>
        </form>
        <div className="chips" role="group" aria-label="Criterios">
          {basicos.map((b) => chip(b, estado.criterios.findIndex((c) => c.campo === b.clave), b.clave))}
          {otros.map(({ c, i }) => {
            const campo = porClave.get(c.campo);
            return campo ? chip(campo, i, `${i}`) : (
              <button key={i} type="button" className="chip invalido" onClick={() => quitar(i)} title="Este campo ya no existe; clic para quitarlo">
                {c.campo} ✕
              </button>
            );
          })}
          <button type="button" className="chip mas" aria-expanded={panel === 'campos'} onClick={() => { setEdicion(null); setPanel(panel === 'campos' ? null : 'campos'); }}>
            + Más criterios
          </button>
          {estado.criterios.length > 0 && (
            <button type="button" className="enlace" onClick={() => { setTexto(''); cambiar({ criterios: [] }); setEdicion(null); }}>Limpiar</button>
          )}
        </div>
      </div>

      {panel === 'campos' && (
        <SelectorCampos campos={campos.filter((c) => c.clave !== 'texto' && !CAMPOS_BASICOS.includes(c.clave))}
                        onElegir={(c) => abrir(c, -1)} onCerrar={() => setPanel(null)} />
      )}
      {edicion && porClave.get(edicion.borrador.campo) && (
        <EditorCriterio key={`${edicion.indice}-${edicion.borrador.campo}`} campo={porClave.get(edicion.borrador.campo)!} inicial={edicion.borrador}
                        existente={edicion.indice !== null}
                        onAplicar={(b) => aplicar({ ...edicion, borrador: b })} onQuitar={() => quitar(edicion.indice)} onCerrar={() => setEdicion(null)} />
      )}

      <div className="herramientas-resultado">
        <span className="secundario" role="status" aria-live="polite">
          {cargando ? 'Buscando…' : total === 0 ? 'Sin resultados' : `${desde.toLocaleString('es-MX')}–${hasta.toLocaleString('es-MX')} de ${total.toLocaleString('es-MX')} issues`}
        </span>
        <div className="acciones">
          <button type="button" className="boton secundario-btn" aria-expanded={panel === 'columnas'} onClick={() => { setEdicion(null); setPanel(panel === 'columnas' ? null : 'columnas'); }}>
            Columnas
          </button>
          {total > 0 && <button type="button" className="boton secundario-btn" onClick={() => void descargar()} title="Hasta 500 issues">Descargar CSV</button>}
          {puedeGuardarFiltro && (
            <button type="button" className="boton secundario-btn" onClick={() => { setEdicion(null); setPanel(panel === 'guardar' ? null : 'guardar'); }}>
              Guardar como filtro
            </button>
          )}
        </div>
      </div>

      {panel === 'columnas' && (
        <EditorColumnas campos={campos} columnas={columnasEfectivas(estado, campos)} personalizadas={estado.columnas.length > 0}
                        onCambio={(cols) => setEstado((e) => ({ ...e, columnas: cols }))} onCerrar={() => setPanel(null)} />
      )}
      {panel === 'guardar' && (
        <GuardarFiltro proc={proc}
                       // Para los tableros: hasta 500 issues por consulta (conteos y barras sobre más que una página).
                       valores={{ ...aParametros({ ...estado, pagina: 1 }, campos), TamanoPagina: '500' }}
                       onGuardado={(n) => { setPanel(null); setAviso(`Filtro «${n}» guardado. Puede usarlo en un widget de sus tableros.`); }}
                       onCancelar={() => setPanel(null)} />
      )}
      {aviso && <p className="secundario" role="status">{aviso}</p>}
      {error && <p className="alerta" role="alert">{error}</p>}

      {resultado && resultado.filas.length === 0 && !cargando && <p className="vacio">No hay issues con estos criterios.</p>}
      {resultado && resultado.filas.length > 0 && (
        <div className={`contenedor-tabla${cargando ? ' cargando' : ''}`}>
          <table>
            <thead>
              <tr>
                {columnas.map((c) => {
                  const campo = porAlias.get(c.nombre);
                  const activa = campo?.clave === estado.ordenarPor;
                  const ordenable = campo && !campo.multivalor;
                  return (
                    <th key={c.nombre} scope="col" className={esNumero(c.tipo) ? 'num' : undefined}
                        aria-sort={activa ? (estado.descendente ? 'descending' : 'ascending') : undefined}>
                      {ordenable ? (
                        <button type="button" onClick={() => ordenarPor(c.nombre)}>
                          {campo.etiqueta}<span aria-hidden="true">{activa ? (estado.descendente ? ' ▼' : ' ▲') : ''}</span>
                        </button>
                      ) : (campo?.etiqueta ?? c.nombre)}
                    </th>
                  );
                })}
              </tr>
            </thead>
            <tbody>
              {resultado.filas.map((f) => (
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
          <button type="button" className="boton secundario-btn" disabled={estado.pagina <= 1} onClick={() => setEstado((e) => ({ ...e, pagina: e.pagina - 1 }))}>← Anterior</button>
          <span>Página {estado.pagina} de {paginas}</span>
          <button type="button" className="boton secundario-btn" disabled={estado.pagina >= paginas} onClick={() => setEstado((e) => ({ ...e, pagina: e.pagina + 1 }))}>Siguiente →</button>
        </nav>
      )}
    </section>
  );
}

/** Parámetros tipados para el procedimiento. */
function cuerpo(p: Record<string, string>, pagina: number, tamano: number): Record<string, unknown> {
  return {
    ...(p.Criterios ? { Criterios: p.Criterios } : {}),
    ...(p.Columnas ? { Columnas: p.Columnas } : {}),
    ...(p.OrdenarPor ? { OrdenarPor: p.OrdenarPor } : {}),
    Descendente: p.Descendente !== 'false',
    Pagina: pagina,
    TamanoPagina: tamano,
  };
}

/* ---------------------------------------------------------------------------------------------------------------- */

function SelectorCampos({ campos, onElegir, onCerrar }: { campos: CampoBuscador[]; onElegir: (c: CampoBuscador) => void; onCerrar: () => void }) {
  const [filtro, setFiltro] = useState('');
  const normal = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
  const visibles = campos.filter((c) => normal(c.etiqueta).includes(normal(filtro)));
  const grupos = [
    { titulo: 'Campos de Jira', lista: visibles.filter((c) => c.origen === 'Jira') },
    { titulo: 'Campos personalizados', lista: visibles.filter((c) => c.origen !== 'Jira') },
  ].filter((g) => g.lista.length);
  return (
    <div className="panel-flotante" role="dialog" aria-label="Agregar criterio" onKeyDown={(e) => e.key === 'Escape' && onCerrar()}>
      <label htmlFor="bq-campo" className="solo-lectores">Buscar campo</label>
      <input id="bq-campo" type="search" placeholder="Buscar campo…" value={filtro} onChange={(e) => setFiltro(e.target.value)} autoFocus />
      {grupos.length === 0 && <p className="vacio">Ningún campo coincide.</p>}
      {grupos.map((g) => (
        <div key={g.titulo} className="grupo-campos">
          <h4>{g.titulo}</h4>
          <ul>
            {g.lista.map((c) => (
              <li key={c.clave}><button type="button" className="opcion" onClick={() => onElegir(c)}>{c.etiqueta}</button></li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

interface PropsEditor {
  campo: CampoBuscador;
  inicial: Criterio;
  existente: boolean;
  onAplicar: (c: Criterio) => void;
  onQuitar: () => void;
  onCerrar: () => void;
}

/** Operador y valor(es) de un criterio; el control depende del tipo del campo. */
function EditorCriterio({ campo, inicial, existente, onAplicar, onQuitar, onCerrar }: PropsEditor) {
  const [c, setC] = useState<Criterio>(inicial);
  const set = (x: Partial<Criterio>) => setC((v) => ({ ...v, ...x }));
  const listo = criterioCompleto(c, campo);
  const tipoInput = campo.tipo === 'numero' ? 'number' : 'text';

  const valor = (clave: 'valor' | 'hasta', etiqueta: string) =>
    campo.tipo === 'fecha' ? (
      <ControlFecha id={`bq-${clave}`} etiqueta={etiqueta} valor={c[clave] ?? ''} onCambio={(v) => set({ [clave]: v })} />
    ) : campo.tipo === 'bit' ? (
      <div className="campo">
        <label htmlFor={`bq-${clave}`}>{etiqueta}</label>
        <select id={`bq-${clave}`} value={c[clave] ?? ''} onChange={(e) => set({ [clave]: e.target.value })}>
          <option value="">Seleccione…</option>
          <option value="1">Sí</option>
          <option value="0">No</option>
        </select>
      </div>
    ) : (
      <div className="campo">
        <label htmlFor={`bq-${clave}`}>{etiqueta}</label>
        <input id={`bq-${clave}`} type={tipoInput} step="any" value={c[clave] ?? ''} onChange={(e) => set({ [clave]: e.target.value })} autoFocus={clave === 'valor'} />
      </div>
    );

  return (
    <form className="panel-flotante editor-criterio" role="dialog" aria-label={`Criterio: ${campo.etiqueta}`}
          onSubmit={(e) => { e.preventDefault(); if (listo) onAplicar(c); }} onKeyDown={(e) => e.key === 'Escape' && onCerrar()}>
      <h4>{campo.etiqueta}{campo.origen !== 'Jira' && <span className="secundario"> · personalizado</span>}</h4>
      <div className="campos">
        {campo.operadores.length > 1 && (
          <div className="campo">
            <label htmlFor="bq-operador">Condición</label>
            <select id="bq-operador" value={c.operador} onChange={(e) => set({ operador: e.target.value as Criterio['operador'] })}>
              {campo.operadores.map((o) => <option key={o} value={o}>{OPERADORES[o]}</option>)}
            </select>
          </div>
        )}
        {!sinValor(c.operador) && !usaLista(c.operador) && valor('valor', c.operador === 'entre' ? 'De' : 'Valor')}
        {c.operador === 'entre' && valor('hasta', 'A')}
      </div>
      {usaLista(c.operador) && <SelectorValores campo={campo.clave} seleccionados={c.valores ?? []} onCambio={(v) => set({ valores: v })} />}
      <div className="acciones">
        <button type="submit" className="boton" disabled={!listo}>Aplicar</button>
        {existente && <button type="button" className="boton secundario-btn" onClick={onQuitar}>Quitar criterio</button>}
        <button type="button" className="enlace" onClick={onCerrar}>Cancelar</button>
      </div>
    </form>
  );
}

function ControlFecha({ id, etiqueta, valor, onCambio }: { id: string; etiqueta: string; valor: string; onCambio: (v: string) => void }) {
  const relativa = FECHAS_RELATIVAS.some((f) => f.valor === valor) || /^\{hoy[+-]\d+\}$/.test(valor);
  return (
    <div className="campo control-fecha">
      <label htmlFor={id}>{etiqueta}</label>
      <select aria-label={`${etiqueta}: tipo de fecha`} value={relativa ? valor : ''} onChange={(e) => onCambio(e.target.value)}>
        <option value="">Fecha fija…</option>
        {FECHAS_RELATIVAS.map((f) => <option key={f.valor} value={f.valor}>{f.etiqueta}</option>)}
      </select>
      {!relativa && <input id={id} type="date" value={valor} onChange={(e) => onCambio(e.target.value)} />}
    </div>
  );
}

/** Lista de valores existentes (con cuántos issues tiene cada uno) con búsqueda, como los filtros de Jira. */
function SelectorValores({ campo, seleccionados, onCambio }: { campo: string; seleccionados: string[]; onCambio: (v: string[]) => void }) {
  const [texto, setTexto] = useState('');
  const [valores, setValores] = useState<{ valor: string; issues: number }[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let vigente = true;
    const t = setTimeout(() => {
      api.ejecutar('Issues_Valores', { Campo: campo, ...(texto.trim() ? { Texto: texto.trim() } : {}), Top: 100 })
        .then((r) => vigente && setValores((r.resultados[0]?.filas ?? []).map((f) => ({ valor: String(f.Valor), issues: Number(f.Issues) }))))
        .catch((e) => vigente && setError(mensaje(e, 'No se pudieron cargar los valores.')));
    }, texto ? 250 : 0);
    return () => { vigente = false; clearTimeout(t); };
  }, [campo, texto]);

  const alternar = (v: string) => onCambio(seleccionados.includes(v) ? seleccionados.filter((x) => x !== v) : [...seleccionados, v]);
  const fuera = seleccionados.filter((s) => !valores?.some((v) => v.valor === s));

  return (
    <div className="selector-valores">
      <label htmlFor="bq-valores" className="solo-lectores">Buscar valor</label>
      <input id="bq-valores" type="search" placeholder="Buscar valor…" value={texto} onChange={(e) => setTexto(e.target.value)} autoFocus />
      {error && <p className="alerta" role="alert">{error}</p>}
      <ul role="group" aria-label="Valores">
        {fuera.map((v) => (
          <li key={`s-${v}`}><label className="casilla"><input type="checkbox" checked onChange={() => alternar(v)} /> {v}</label></li>
        ))}
        {valores?.map((v) => (
          <li key={v.valor}>
            <label className="casilla">
              <input type="checkbox" checked={seleccionados.includes(v.valor)} onChange={() => alternar(v.valor)} />
              {v.valor} <span className="secundario">({v.issues.toLocaleString('es-MX')})</span>
            </label>
          </li>
        ))}
        {valores?.length === 0 && fuera.length === 0 && <li className="secundario">Sin valores.</li>}
        {valores === null && !error && <li className="secundario">Cargando…</li>}
      </ul>
    </div>
  );
}

interface PropsColumnas {
  campos: CampoBuscador[];
  columnas: string[];
  personalizadas: boolean;
  onCambio: (columnas: string[]) => void;
  onCerrar: () => void;
}

/** Qué columnas mostrar y en qué orden (la clave siempre va primero). */
function EditorColumnas({ campos, columnas, personalizadas, onCambio, onCerrar }: PropsColumnas) {
  const nombre = (k: string) => campos.find((c) => c.clave === k)?.etiqueta ?? k;
  const disponibles = campos.filter((c) => c.esColumna && !columnas.includes(c.clave));
  return (
    <div className="panel-flotante editor-columnas" role="dialog" aria-label="Columnas" onKeyDown={(e) => e.key === 'Escape' && onCerrar()}>
      <h4>Columnas</h4>
      <ol>
        {columnas.map((k, i) => (
          <li key={k}>
            <span>{nombre(k)}</span>
            {k !== 'clave' && (
              <span className="mover">
                <button type="button" className="icono" aria-label={`Subir ${nombre(k)}`} disabled={i <= 1} onClick={() => onCambio(moverColumna(columnas, k, -1))}>↑</button>
                <button type="button" className="icono" aria-label={`Bajar ${nombre(k)}`} disabled={i === columnas.length - 1} onClick={() => onCambio(moverColumna(columnas, k, 1))}>↓</button>
                <button type="button" className="icono" aria-label={`Quitar ${nombre(k)}`} onClick={() => onCambio(columnas.filter((x) => x !== k))}>✕</button>
              </span>
            )}
          </li>
        ))}
      </ol>
      <div className="campos">
        <div className="campo">
          <label htmlFor="bq-agregar-columna">Agregar columna</label>
          <select id="bq-agregar-columna" value="" onChange={(e) => e.target.value && onCambio([...columnas, e.target.value])}>
            <option value="">Seleccione…</option>
            <optgroup label="Campos de Jira">
              {disponibles.filter((c) => c.origen === 'Jira').map((c) => <option key={c.clave} value={c.clave}>{c.etiqueta}</option>)}
            </optgroup>
            <optgroup label="Campos personalizados">
              {disponibles.filter((c) => c.origen !== 'Jira').map((c) => <option key={c.clave} value={c.clave}>{c.etiqueta}</option>)}
            </optgroup>
          </select>
        </div>
      </div>
      <div className="acciones">
        <button type="button" className="boton" onClick={onCerrar}>Listo</button>
        {personalizadas && <button type="button" className="boton secundario-btn" onClick={() => onCambio([])}>Predeterminadas</button>}
      </div>
    </div>
  );
}
