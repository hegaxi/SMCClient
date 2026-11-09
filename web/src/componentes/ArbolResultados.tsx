import { useMemo, useState } from 'react';
import { aCsv, esNumero, etiqueta, formatear } from '../formato';
import type { ColumnaInfo, ConjuntoResultados, Fila } from '../tipos';

/** Columnas que arman el árbol y no se muestran (NivelNombre: "Persona", "Épica"… para los botones "Ver …"). */
const COLUMNAS_ARBOL = ['Nodo', 'PadreNodo', 'Nivel'];
const COLUMNAS_OCULTAS = [...COLUMNAS_ARBOL, 'NivelNombre', 'Clave'];
/** Al abrir, se despliegan niveles mientras quepan en esta cantidad de filas. */
// Filas que se muestran al cargar: se abren niveles completos mientras quepan (un periodo corto abre todo el árbol).
const FILAS_AL_ABRIR = 150;

/** "Épica" -> "épicas", "Proyecto" -> "proyectos". */
const plural = (s: string) => { const x = s.toLocaleLowerCase('es-MX'); return /[aeiouáéíóú]$/.test(x) ? `${x}s` : `${x}es`; };

/** Un conjunto de resultados es un árbol si trae Nodo, PadreNodo y Nivel (p. ej. api.Horas_Arbol). */
export const esArbol = (c: ConjuntoResultados) => COLUMNAS_ARBOL.every((n) => c.columnas.some((x) => x.nombre === n));

interface Props {
  conjunto: ConjuntoResultados;
  titulo?: string | null;
  nombreArchivo: string;
  onAbrirClave?: (clave: string) => void;
  /** Niveles abiertos al cargar; por omisión, los que quepan en unas 150 filas. */
  nivelesAbiertos?: number;
}

/**
 * Árbol con columnas (treegrid): cada fila se abre o se cierra para ver lo que tiene debajo. La primera columna visible
 * lleva la sangría, el botón para abrir y la clave (que abre el detalle).
 */
export function ArbolResultados({ conjunto, titulo, nombreArchivo, onAbrirClave, nivelesAbiertos }: Props) {
  const columnas = conjunto.columnas.filter((c) => !COLUMNAS_OCULTAS.includes(c.nombre));
  const [principal, ...resto] = columnas;

  const { hijos, raices, nivelDe } = useMemo(() => {
    const hijos = new Map<string, Fila[]>();
    const nodos = new Set(conjunto.filas.map((f) => String(f.Nodo)));
    const raices: Fila[] = [];
    for (const f of conjunto.filas) {
      const padre = f.PadreNodo == null ? null : String(f.PadreNodo);
      if (padre && nodos.has(padre)) {
        if (!hijos.has(padre)) hijos.set(padre, []);
        hijos.get(padre)!.push(f);
      } else raices.push(f);
    }
    return { hijos, raices, nivelDe: (f: Fila) => Number(f.Nivel ?? 0) };
  }, [conjunto.filas]);

  // Niveles presentes (con su nombre, si viene NivelNombre) y cuántas filas tiene cada uno.
  const niveles = useMemo(() => {
    const m = new Map<number, { nombre: string | null; filas: number }>();
    for (const f of conjunto.filas) {
      const n = nivelDe(f);
      const x = m.get(n) ?? { nombre: f.NivelNombre == null ? null : String(f.NivelNombre), filas: 0 };
      x.filas += 1;
      m.set(n, x);
    }
    return [...m.entries()].sort(([a], [b]) => a - b);
  }, [conjunto.filas, nivelDe]);
  const abiertosAlCargar = () => {
    if (nivelesAbiertos !== undefined) return nivelesAbiertos;
    let n = 1, visibles = niveles[0]?.[1].filas ?? 0;
    while (n < niveles.length && visibles + niveles[n][1].filas <= FILAS_AL_ABRIR) { visibles += niveles[n][1].filas; n += 1; }
    return niveles[n - 1]?.[0] ?? 0;
  };
  const inicial = () => { const hasta = abiertosAlCargar(); return new Set(conjunto.filas.filter((f) => nivelDe(f) < hasta).map((f) => String(f.Nodo))); };
  const [abiertos, setAbiertos] = useState<Set<string>>(inicial);
  const alternar = (n: string) => setAbiertos((a) => { const x = new Set(a); if (x.has(n)) x.delete(n); else x.add(n); return x; });
  const abrirHasta = (nivel: number) => setAbiertos(new Set(conjunto.filas.filter((f) => nivelDe(f) < nivel).map((f) => String(f.Nodo))));

  // Filas visibles en orden: cada una seguida de sus hijos si está abierta.
  const visibles: Fila[] = [];
  const recorrer = (lista: Fila[]) => {
    for (const f of lista) {
      visibles.push(f);
      const n = String(f.Nodo);
      if (abiertos.has(n)) recorrer(hijos.get(n) ?? []);
    }
  };
  recorrer(raices);

  const descargar = () => {
    // El CSV lleva todas las filas, con la sangría del nivel en la primera columna.
    const filas = conjunto.filas.map((f) => ({ ...f, [principal.nombre]: `${'  '.repeat(nivelDe(f))}${f.Clave ? `${String(f.Clave)} · ` : ''}${String(f[principal.nombre] ?? '')}` }));
    const url = URL.createObjectURL(new Blob([aCsv([{ nombre: 'Nivel', tipo: 'int', nulo: false }, ...columnas], filas)], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${nombreArchivo}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const valor = (f: Fila, c: ColumnaInfo) => formatear(f[c.nombre], c.tipo);

  return (
    <section className="resultado">
      <div className="encabezado-resultado">
        {titulo && <h3>{titulo}</h3>}
        <span className="contador">{conjunto.filas.length.toLocaleString('es-MX')} elementos</span>
        <div className="acciones-arbol">
          {/* "Ver épicas": abre hasta que se vean las épicas (sin pasar del penúltimo nivel). */}
          {niveles.slice(1, -1).map(([n, x]) => (
            <button key={n} type="button" className="boton secundario-btn pequeno" onClick={() => abrirHasta(n)}>
              Ver {x.nombre ? plural(x.nombre) : `nivel ${n}`}
            </button>
          ))}
          <button type="button" className="boton secundario-btn pequeno" onClick={() => abrirHasta(99)}>Abrir todo</button>
          <button type="button" className="boton secundario-btn pequeno" onClick={() => abrirHasta(0)}>Cerrar todo</button>
          <button type="button" className="boton secundario-btn pequeno" onClick={descargar}>Descargar CSV</button>
        </div>
      </div>
      {conjunto.truncado && <p className="alerta">Se muestran solo los primeros {conjunto.filas.length.toLocaleString('es-MX')} elementos.</p>}
      {conjunto.filas.length === 0 ? <p className="vacio">No hay registros con estos filtros.</p> : (
        <div className="contenedor-tabla">
          <table className="arbol" role="treegrid" aria-label={titulo ?? 'Árbol'}>
            <thead>
              <tr>
                <th scope="col">{etiqueta(principal.nombre)}</th>
                {resto.map((c) => <th key={c.nombre} scope="col" className={esNumero(c.tipo) ? 'num' : undefined}>{etiqueta(c.nombre)}</th>)}
              </tr>
            </thead>
            <tbody>
              {visibles.map((f) => {
                const n = String(f.Nodo);
                const nivel = nivelDe(f);
                const tieneHijos = (hijos.get(n)?.length ?? 0) > 0;
                const abierto = abiertos.has(n);
                const clave = f.Clave == null ? null : String(f.Clave);
                return (
                  <tr key={n} aria-level={nivel + 1} aria-expanded={tieneHijos ? abierto : undefined} className={`nivel-${Math.min(nivel, 4)}`}>
                    <td className="celda-arbol" style={{ paddingLeft: `${0.5 + nivel * 1.25}rem` }}>
                      {tieneHijos ? (
                        <button type="button" className="alternar-nodo" aria-label={`${abierto ? 'Cerrar' : 'Abrir'} ${clave ?? String(f[principal.nombre] ?? '')}`}
                                onClick={() => alternar(n)}>{abierto ? '▾' : '▸'}</button>
                      ) : <span className="alternar-nodo vacio-nodo" aria-hidden="true" />}
                      {clave && (onAbrirClave
                        ? <button type="button" className="enlace clave-nodo" onClick={() => onAbrirClave(clave)} title={`Ver el detalle de ${clave}`}>{clave}</button>
                        : <span className="clave-nodo">{clave}</span>)}
                      <span className="texto-nodo">{valor(f, principal)}</span>
                    </td>
                    {resto.map((c) => <td key={c.nombre} className={esNumero(c.tipo) ? 'num' : undefined}>{valor(f, c)}</td>)}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
