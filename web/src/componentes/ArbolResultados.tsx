import { useMemo, useState, type KeyboardEvent } from 'react';
import { aCsv, claseSituacion, esDesviacion, esNumero, etiqueta, formatear } from '../formato';
import type { ColumnaInfo, ConjuntoResultados, Fila } from '../tipos';

/** Columnas que arman el árbol y no se muestran (NivelNombre: "Persona", "Épica"… para los botones "Ver …"). */
const COLUMNAS_ARBOL = ['Nodo', 'PadreNodo', 'Nivel'];
const COLUMNAS_OCULTAS = [...COLUMNAS_ARBOL, 'NivelNombre', 'Clave'];
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
  /** Columnas ocultas hasta "Más columnas" (smc:columnasSecundarias). */
  columnasSecundarias?: string[] | null;
  /** Qué significa cada columna (smc:ayudaColumnas): se ve al pasar sobre el encabezado. */
  ayudaColumnas?: Record<string, string> | null;
}

/**
 * Árbol con columnas (treegrid): cada fila se abre o se cierra para ver lo que tiene debajo. La primera columna visible
 * lleva la sangría, el botón para abrir y la clave (que abre el detalle); queda fija al desplazar a la derecha.
 */
export function ArbolResultados({ conjunto, titulo, nombreArchivo, onAbrirClave, nivelesAbiertos, columnasSecundarias, ayudaColumnas }: Props) {
  const [masColumnas, setMasColumnas] = useState(false);
  const todas = conjunto.columnas.filter((c) => !COLUMNAS_OCULTAS.includes(c.nombre));
  const secundarias = new Set((columnasSecundarias ?? []).filter((n) => todas.some((c) => c.nombre === n)));
  const columnas = masColumnas ? todas : todas.filter((c) => !secundarias.has(c.nombre));
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
  const fijar = (n: string, abrir: boolean) => setAbiertos((a) => { const x = new Set(a); if (abrir) x.add(n); else x.delete(n); return x; });
  const alternar = (n: string) => fijar(n, !abiertos.has(n));
  const abrirHasta = (nivel: number) => setAbiertos(new Set(conjunto.filas.filter((f) => nivelDe(f) < nivel).map((f) => String(f.Nodo))));
  // Teclado como en un treegrid: → abre, ← cierra; ↑/↓ pasan al primer botón de la fila vecina.
  const teclas = (e: KeyboardEvent<HTMLButtonElement>, n: string) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); fijar(n, true); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); fijar(n, false); }
    else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const fila = e.currentTarget.closest('tr');
      const vecina = (e.key === 'ArrowDown' ? fila?.nextElementSibling : fila?.previousElementSibling) as HTMLElement | null;
      vecina?.querySelector<HTMLElement>('button')?.focus();
    }
  };

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
    // Todas las filas y columnas; Nivel, tipo de nivel y clave en columnas propias (se filtran en Excel) y encabezados legibles.
    const cols = ['Nivel', 'NivelNombre', 'Clave', ...todas.map((c) => c.nombre)];
    const encabezados = cols.map((c) => (c === 'NivelNombre' ? 'Tipo de nivel' : etiqueta(c)));
    const filas = conjunto.filas.map((f) => Object.fromEntries(cols.map((c, i) => [encabezados[i], f[c]])));
    const url = URL.createObjectURL(new Blob([aCsv(encabezados.map((nombre) => ({ nombre })), filas)], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${nombreArchivo}.csv`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);   // revocarlo de inmediato cancela la descarga en algunos navegadores
  };

  const valor = (f: Fila, c: ColumnaInfo) => {
    // Número vacío = sin tiempo: celda en blanco (con muchas columnas por periodo, los "—" no dejan ver los valores).
    if (esNumero(c.tipo) && f[c.nombre] == null) return '';
    const texto = formatear(f[c.nombre], c.tipo, c.nombre);
    const situacion = claseSituacion(c.nombre, f[c.nombre]);
    return situacion ? <span className={`estado-situacion ${situacion}`}>{texto}</span> : texto;
  };
  const claseCelda = (f: Fila, c: ColumnaInfo) =>
    [esNumero(c.tipo) ? 'num' : '', esDesviacion(c.nombre) && Number(f[c.nombre]) > 0 ? 'desviacion-positiva' : ''].join(' ').trim() || undefined;
  const encabezado = (c: ColumnaInfo) =>
    ayudaColumnas?.[c.nombre] ? <abbr className="ayuda-columna" title={ayudaColumnas[c.nombre]}>{etiqueta(c.nombre)}</abbr> : etiqueta(c.nombre);

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
          {secundarias.size > 0 && (
            <button type="button" className="boton secundario-btn pequeno" aria-pressed={masColumnas} onClick={() => setMasColumnas((x) => !x)}
                    title={[...secundarias].map(etiqueta).join(', ')}>
              {masColumnas ? 'Menos columnas' : `Más columnas (${secundarias.size})`}
            </button>
          )}
          <button type="button" className="boton secundario-btn pequeno" onClick={descargar}>Descargar CSV</button>
        </div>
      </div>
      {conjunto.truncado && <p className="alerta">Se muestran solo los primeros {conjunto.filas.length.toLocaleString('es-MX')} elementos.</p>}
      {conjunto.filas.length === 0 || !principal ? <p className="vacio">No hay registros con estos filtros.</p> : (
        <div className="contenedor-tabla">
          <table className="arbol" role="treegrid" aria-label={titulo ?? 'Árbol'}>
            <thead>
              <tr>
                <th scope="col">{encabezado(principal)}</th>
                {resto.map((c) => <th key={c.nombre} scope="col" className={esNumero(c.tipo) ? 'num' : undefined}>{encabezado(c)}</th>)}
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
                  <tr key={n} role="row" aria-level={nivel + 1} aria-expanded={tieneHijos ? abierto : undefined} className={`nivel-${Math.min(nivel, 4)}`}>
                    <td className="celda-arbol" style={{ paddingLeft: `${0.5 + nivel * 1.25}rem` }}>
                      {tieneHijos ? (
                        <button type="button" className="alternar-nodo" aria-label={`${abierto ? 'Cerrar' : 'Abrir'} ${clave ?? String(f[principal.nombre] ?? '')}`}
                                onClick={() => alternar(n)} onKeyDown={(e) => teclas(e, n)}>{abierto ? '▾' : '▸'}</button>
                      ) : <span className="alternar-nodo vacio-nodo" aria-hidden="true" />}
                      {clave && (onAbrirClave
                        ? <button type="button" className="enlace clave-nodo" onClick={() => onAbrirClave(clave)} title={`Ver el detalle de ${clave}`}>{clave}</button>
                        : <span className="clave-nodo">{clave}</span>)}
                      <span className="texto-nodo">{valor(f, principal)}</span>
                    </td>
                    {resto.map((c) => <td key={c.nombre} className={claseCelda(f, c)}>{valor(f, c)}</td>)}
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
