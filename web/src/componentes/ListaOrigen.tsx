import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { api } from '../api';
import type { OrigenParametro, ValoresFormulario } from '../tipos';

export interface OpcionLista {
  valor: string;
  etiqueta: string;
  descripcion: string | null;
}

/** Usuarios y roles para "Compartir con" (tableros y consultas personalizadas); formato de @CompartirCon. */
export const DESTINATARIOS: OrigenParametro = {
  procedimiento: 'Destinatarios_Listar', valor: 'Valor', etiqueta: 'Etiqueta', descripcion: 'Tipo', libre: false,
};

/** Las listas se piden una vez por combinación de parámetros; las acciones que modifican datos limpian el caché. */
const cache = new Map<string, Promise<OpcionLista[]>>();

export function limpiarCacheListas() {
  cache.clear();
}

const texto = (v: unknown) => (v === null || v === undefined ? '' : String(v));

/** Parámetros del origen con los valores actuales del formulario ("@Proyecto" -> el proyecto elegido). Vacíos se omiten. */
export function parametrosDeOrigen(origen: OrigenParametro, valores: ValoresFormulario = {}): Record<string, string> {
  const r: Record<string, string> = {};
  for (const [k, v] of Object.entries(origen.parametros ?? {})) {
    const x = v.startsWith('@') ? (valores[v.slice(1)] ?? '').trim() : v;
    if (x !== '') r[k] = x;
  }
  return r;
}

export function cargarOpciones(origen: OrigenParametro, parametros: Record<string, string> = {}): Promise<OpcionLista[]> {
  const clave = [origen.procedimiento, origen.valor, origen.etiqueta, origen.descripcion, JSON.stringify(parametros)].join('|');
  let p = cache.get(clave);
  if (!p) {
    p = api.ejecutar(origen.procedimiento, parametros).then((r) => {
      const vistos = new Set<string>();
      const opciones: OpcionLista[] = [];
      for (const f of r.resultados[0]?.filas ?? []) {
        const valor = texto(f[origen.valor]).trim();
        if (!valor || vistos.has(valor)) continue;
        vistos.add(valor);
        const etiqueta = texto(origen.etiqueta ? f[origen.etiqueta] : '').trim() || valor;
        const descripcion = origen.descripcion ? texto(f[origen.descripcion]).trim() || null : null;
        opciones.push({ valor, etiqueta, descripcion: descripcion === etiqueta ? null : descripcion });
      }
      return opciones;
    });
    p.catch(() => cache.delete(clave)); // un error (p. ej. sin permiso) no se queda guardado
    cache.set(clave, p);
  }
  return p;
}

/** "a, b" -> ["a", "b"] con el separador declarado (smc:multiple). */
export const separar = (valor: string, separador: string) =>
  valor.split(separador).map((x) => x.trim()).filter(Boolean);

/** Una lista de un valor con más opciones que esto se elige escribiendo (combobox con búsqueda). */
const LIMITE_DESPLEGABLE = 15;

interface Props {
  id: string;
  /** id de la etiqueta visible del campo (para nombrar el grupo de casillas o el combobox). */
  etiquetaId: string;
  origen: OrigenParametro;
  /** Separador si se pueden elegir varios; null = uno solo. */
  multiple: string | null;
  valor: string;
  onCambio: (valor: string) => void;
  opcional: boolean;
  /** Valores del formulario: los usan las listas que dependen de otro campo (sprints del proyecto elegido). */
  valoresFormulario?: ValoresFormulario;
  /** Texto de la primera opción de una lista de un solo valor ("Todos", "Seleccione…"). */
  textoVacio?: string;
  describedBy?: string;
  invalido?: boolean;
  /** Control de texto que se muestra si la lista no se puede cargar (p. ej. el usuario no tiene ese permiso). */
  respaldo: ReactNode;
}

/**
 * Lista que sale de otro procedimiento (smc:origen): desplegable para pocas opciones, combobox con búsqueda para muchas
 * o si también se puede escribir un valor nuevo (smc:origenLibre), y casillas con búsqueda para varios valores.
 */
export function ListaOrigen({ id, etiquetaId, origen, multiple, valor, onCambio, opcional, valoresFormulario, textoVacio, describedBy, invalido, respaldo }: Props) {
  const [opciones, setOpciones] = useState<OpcionLista[] | null>(null);
  const [fallo, setFallo] = useState(false);
  const [filtro, setFiltro] = useState('');
  const parametros = useMemo(() => parametrosDeOrigen(origen, valoresFormulario), [origen, valoresFormulario]);
  const claveParametros = JSON.stringify(parametros);

  useEffect(() => {
    let vigente = true;
    setOpciones(null);
    cargarOpciones(origen, JSON.parse(claveParametros) as Record<string, string>)
      .then((o) => vigente && setOpciones(o)).catch(() => vigente && setFallo(true));
    return () => { vigente = false; };
  }, [origen, claveParametros]);

  // Obligatorio y con una sola opción posible (p. ej. una sola fuente de Jira): se elige sola. No en una lista libre
  // (alta de un usuario: que exista un solo usuario no significa que se quiera editar ése).
  useEffect(() => {
    if (!multiple && !opcional && !origen.libre && !valor && opciones?.length === 1) onCambio(opciones[0].valor);
  }, [multiple, opcional, origen.libre, valor, opciones, onCambio]);

  const seleccionados = useMemo(() => (multiple ? separar(valor, multiple) : []), [valor, multiple]);

  if (fallo) return <>{respaldo}</>;
  const comunes = { 'aria-describedby': describedBy, 'aria-invalid': invalido || undefined };

  if (opciones === null) {
    return multiple
      ? <p className="secundario lista-cargando" role="status">Cargando opciones…</p>
      : <select id={id} disabled {...comunes}><option>Cargando…</option></select>;
  }

  const textoOpcion = (o: OpcionLista) => (o.descripcion ? `${o.etiqueta} — ${o.descripcion}` : o.etiqueta);

  if (!multiple && (origen.libre || opciones.length > LIMITE_DESPLEGABLE)) {
    return (
      <Combobox id={id} etiquetaId={etiquetaId} opciones={opciones} valor={valor} onCambio={onCambio} libre={origen.libre}
                requerido={!opcional} describedBy={describedBy} invalido={invalido} />
    );
  }

  if (!multiple) {
    const fuera = valor && !opciones.some((o) => o.valor === valor); // p. ej. un valor que llegó en la dirección
    return (
      <select id={id} value={valor} required={!opcional} {...comunes} onChange={(e) => onCambio(e.target.value)}>
        <option value="">{opcional ? (textoVacio ?? 'Todos') : 'Seleccione…'}</option>
        {fuera && <option value={valor}>{valor}</option>}
        {opciones.map((o) => <option key={o.valor} value={o.valor}>{textoOpcion(o)}</option>)}
      </select>
    );
  }

  const alternar = (v: string) => {
    const nuevos = seleccionados.includes(v) ? seleccionados.filter((x) => x !== v) : [...seleccionados, v];
    onCambio(nuevos.join(multiple));
  };
  const f = filtro.trim().toLocaleLowerCase('es-MX');
  const visibles = f
    ? opciones.filter((o) => `${o.valor} ${o.etiqueta} ${o.descripcion ?? ''}`.toLocaleLowerCase('es-MX').includes(f))
    : opciones;
  const fuera = seleccionados.filter((s) => !opciones.some((o) => o.valor === s));

  return (
    <div className="lista-casillas" role="group" aria-labelledby={etiquetaId} {...comunes}>
      {opciones.length > 8 && (
        <input type="search" className="lista-filtro" placeholder="Buscar…" value={filtro} aria-label="Buscar en la lista"
               onChange={(e) => setFiltro(e.target.value)} />
      )}
      <ul>
        {fuera.map((v) => (
          <li key={`fuera-${v}`}><label className="casilla"><input type="checkbox" checked onChange={() => alternar(v)} /> {v}</label></li>
        ))}
        {visibles.map((o) => (
          <li key={o.valor}>
            <label className="casilla">
              <input type="checkbox" checked={seleccionados.includes(o.valor)} onChange={() => alternar(o.valor)} />
              <span>{o.etiqueta}{o.descripcion && <small className="secundario"> — {o.descripcion}</small>}</span>
            </label>
          </li>
        ))}
        {visibles.length === 0 && fuera.length === 0 && <li className="secundario">{f ? 'Nada coincide.' : 'No hay opciones.'}</li>}
      </ul>
      {seleccionados.length > 0 && (
        <p className="secundario lista-resumen">
          {seleccionados.length} seleccionado(s) · <button type="button" className="enlace" onClick={() => onCambio('')}>Quitar todos</button>
        </p>
      )}
    </div>
  );
}

interface PropsCombobox {
  id: string;
  etiquetaId: string;
  opciones: OpcionLista[];
  valor: string;
  onCambio: (valor: string) => void;
  /** Se acepta lo escrito aunque no esté en la lista. */
  libre: boolean;
  requerido: boolean;
  describedBy?: string;
  invalido?: boolean;
}

const MAX_SUGERENCIAS = 50;

/**
 * Campo con autocompletado (patrón combobox de WAI-ARIA): se escribe para filtrar y se elige con el ratón o con
 * ↑ ↓ Enter; Escape cierra. Muestra la etiqueta de la opción (p. ej. el nombre) aunque el valor sea un id.
 */
export function Combobox({ id, etiquetaId, opciones, valor, onCambio, libre, requerido, describedBy, invalido }: PropsCombobox) {
  const elegida = opciones.find((o) => o.valor === valor);
  const [texto, setTexto] = useState(elegida?.etiqueta ?? valor);
  const [abierto, setAbierto] = useState(false);
  const [activa, setActiva] = useState(0);
  const listaId = useId();
  const editando = useRef(false);

  // Si el valor cambia desde fuera (p. ej. se limpia el formulario), se muestra su etiqueta.
  useEffect(() => {
    if (!editando.current) setTexto(opciones.find((o) => o.valor === valor)?.etiqueta ?? valor);
  }, [valor, opciones]);

  const t = texto.trim().toLocaleLowerCase('es-MX');
  const filtradas = (t && t !== elegida?.etiqueta.toLocaleLowerCase('es-MX')
    ? opciones.filter((o) => `${o.valor} ${o.etiqueta} ${o.descripcion ?? ''}`.toLocaleLowerCase('es-MX').includes(t))
    : opciones);
  const visibles = filtradas.slice(0, MAX_SUGERENCIAS);

  const elegir = (o: OpcionLista) => {
    editando.current = false;
    setTexto(o.etiqueta);
    setAbierto(false);
    onCambio(o.valor);
  };
  const escribir = (v: string) => {
    editando.current = true;
    setTexto(v);
    setAbierto(true);
    setActiva(0);
    if (libre || v.trim() === '') onCambio(v.trim());
  };
  const salir = () => {
    editando.current = false;
    setAbierto(false);
    // Sin valor libre, lo escrito que no es una opción se descarta.
    if (!libre) setTexto(opciones.find((o) => o.valor === valor)?.etiqueta ?? '');
  };
  const teclear = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); setAbierto(true); setActiva((a) => Math.min(a + 1, visibles.length - 1)); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActiva((a) => Math.max(a - 1, 0)); }
    else if (e.key === 'Enter' && abierto && visibles[activa]) { e.preventDefault(); elegir(visibles[activa]); }
    else if (e.key === 'Escape') { setAbierto(false); }
  };

  return (
    <div className="combobox">
      <input id={id} type="text" role="combobox" aria-autocomplete="list" aria-expanded={abierto} aria-controls={listaId}
             aria-activedescendant={abierto && visibles[activa] ? `${listaId}-${activa}` : undefined}
             aria-describedby={describedBy} aria-invalid={invalido || undefined} required={requerido}
             value={texto} autoComplete="off" placeholder={libre ? 'Elija o escriba…' : 'Escriba para buscar…'}
             onChange={(e) => escribir(e.target.value)} onFocus={() => setAbierto(true)} onBlur={salir} onKeyDown={teclear} />
      {abierto && (
        <ul id={listaId} role="listbox" aria-labelledby={etiquetaId} className="combobox-lista">
          {visibles.map((o, i) => (
            <li key={o.valor} id={`${listaId}-${i}`} role="option" aria-selected={o.valor === valor}
                className={i === activa ? 'activa' : undefined}
                onMouseDown={(e) => { e.preventDefault(); elegir(o); }}>
              <span>{o.etiqueta}</span>
              {o.descripcion && <small className="secundario">{o.descripcion}</small>}
            </li>
          ))}
          {filtradas.length > MAX_SUGERENCIAS && <li className="secundario" aria-disabled="true">{filtradas.length - MAX_SUGERENCIAS} más: siga escribiendo…</li>}
          {visibles.length === 0 && <li className="secundario" aria-disabled="true">{libre ? 'Nuevo: se usará lo que escribió.' : 'Nada coincide.'}</li>}
        </ul>
      )}
    </div>
  );
}
