import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { api } from '../api';
import type { OrigenParametro } from '../tipos';

export interface OpcionLista {
  valor: string;
  etiqueta: string;
  descripcion: string | null;
}

/** Las listas se piden una vez por sesión de página; las acciones que modifican datos limpian el caché. */
const cache = new Map<string, Promise<OpcionLista[]>>();

export function limpiarCacheListas() {
  cache.clear();
}

/** Usuarios y roles para "Compartir con" (tableros y consultas personalizadas); formato de @CompartirCon. */
export const DESTINATARIOS: OrigenParametro = {
  procedimiento: 'Destinatarios_Listar', valor: 'Valor', etiqueta: 'Etiqueta', descripcion: 'Tipo', libre: false,
};

const texto = (v: unknown) => (v === null || v === undefined ? '' : String(v));

export function cargarOpciones(origen: OrigenParametro): Promise<OpcionLista[]> {
  const clave = [origen.procedimiento, origen.valor, origen.etiqueta, origen.descripcion].join('|');
  let p = cache.get(clave);
  if (!p) {
    p = api.ejecutar(origen.procedimiento).then((r) => {
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

interface Props {
  id: string;
  /** id de la etiqueta visible del campo (para nombrar el grupo de casillas). */
  etiquetaId: string;
  origen: OrigenParametro;
  /** Separador si se pueden elegir varios; null = uno solo. */
  multiple: string | null;
  valor: string;
  onCambio: (valor: string) => void;
  opcional: boolean;
  /** Texto de la primera opción de una lista de un solo valor ("Todos", "Seleccione…"). */
  textoVacio?: string;
  describedBy?: string;
  invalido?: boolean;
  /** Control de texto que se muestra si la lista no se puede cargar (p. ej. el usuario no tiene ese permiso). */
  respaldo: ReactNode;
}

/**
 * Lista que sale de otro procedimiento (smc:origen): desplegable para un valor, casillas con búsqueda para varios, o
 * texto con sugerencias si también se puede escribir un valor nuevo (smc:origenLibre).
 */
export function ListaOrigen({ id, etiquetaId, origen, multiple, valor, onCambio, opcional, textoVacio, describedBy, invalido, respaldo }: Props) {
  const [opciones, setOpciones] = useState<OpcionLista[] | null>(null);
  const [fallo, setFallo] = useState(false);
  const [filtro, setFiltro] = useState('');

  useEffect(() => {
    let vigente = true;
    cargarOpciones(origen).then((o) => vigente && setOpciones(o)).catch(() => vigente && setFallo(true));
    return () => { vigente = false; };
  }, [origen]);

  // Obligatorio y con una sola opción posible (p. ej. una sola fuente de Jira): se elige sola.
  useEffect(() => {
    if (!multiple && !opcional && !valor && opciones?.length === 1) onCambio(opciones[0].valor);
  }, [multiple, opcional, valor, opciones, onCambio]);

  const seleccionados = useMemo(() => (multiple ? separar(valor, multiple) : []), [valor, multiple]);

  if (fallo) return <>{respaldo}</>;
  const comunes = { 'aria-describedby': describedBy, 'aria-invalid': invalido || undefined };

  if (opciones === null) {
    return multiple
      ? <p className="secundario lista-cargando" role="status">Cargando opciones…</p>
      : <select id={id} disabled {...comunes}><option>Cargando…</option></select>;
  }

  const textoOpcion = (o: OpcionLista) => (o.descripcion ? `${o.etiqueta} — ${o.descripcion}` : o.etiqueta);

  if (!multiple && origen.libre) {
    return (
      <>
        <input id={id} type="text" list={`${id}-opciones`} value={valor} autoComplete="off" {...comunes}
               required={!opcional} onChange={(e) => onCambio(e.target.value)} />
        <datalist id={`${id}-opciones`}>
          {opciones.map((o) => <option key={o.valor} value={o.valor}>{textoOpcion(o)}</option>)}
        </datalist>
      </>
    );
  }

  if (!multiple) {
    const fuera = valor && !opciones.some((o) => o.valor === valor); // p. ej. un valor que llegó en la dirección
    return (
      <select id={id} value={valor} required={!opcional} {...comunes} onChange={(e) => onCambio(e.target.value)}>
        <option value="">{textoVacio ?? (opcional ? 'Todos' : 'Seleccione…')}</option>
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
