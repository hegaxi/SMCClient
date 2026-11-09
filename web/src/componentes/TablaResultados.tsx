import { useMemo, useState, type ReactNode } from 'react';
import type { ConjuntoResultados, Fila } from '../tipos';
import { aCsv, claseSituacion, claveOrden, esDesviacion, esNumero, etiqueta, formatear, opcionesDeColumna } from '../formato';

interface Props {
  conjunto: ConjuntoResultados;
  titulo?: string | null;
  nombreArchivo: string;
  /** Si se indica, los valores de las columnas Clave / PadreClave abren el detalle del issue. */
  onAbrirClave?: (clave: string) => void;
  /** Un solo registro con muchas columnas se muestra como ficha (consultas de detalle). */
  permitirFicha?: boolean;
  /** Etiquetas para valores codificados ("service_desk" -> "Mesa de ayuda"). */
  etiquetasValores?: Map<string, Map<string, string>>;
  /** Mensaje cuando no hay filas (por omisión, el de una consulta con filtros). */
  textoVacio?: string;
  /** Botones de cada fila (acciones del listado: Editar, Eliminar…). */
  accionesFila?: (fila: Fila) => ReactNode;
  /** Qué significa cada columna (smc:ayudaColumnas): se ve al pasar sobre el encabezado. */
  ayudaColumnas?: Record<string, string> | null;
}

const COLUMNAS_CLAVE = new Set(['Clave', 'PadreClave']);
/** Solo una clave de issue (PROYECTO-123) abre el detalle; la clave de un proyecto (SMC26) no. */
const ES_CLAVE_ISSUE = /^[A-Z][A-Z0-9_]*-\d+$/;
/** Columnas de texto que se leen completas (con sus saltos de línea) hasta este largo; más, con "Ver más". */
const COLUMNAS_TEXTO = new Set(['Comentario', 'Cuerpo', 'Descripcion', 'UltimoComentario']);
const COLUMNAS_OCULTAS = new Set(['TotalFilas']);

/** Un conjunto de resultados: ficha si es un solo registro con muchas columnas; si no, tabla ordenable. */
export function TablaResultados({ conjunto, titulo, nombreArchivo, onAbrirClave, permitirFicha = false, etiquetasValores, textoVacio = 'No hay registros con estos filtros.', accionesFila, ayudaColumnas }: Props) {
  const columnas = conjunto.columnas.filter((c) => !COLUMNAS_OCULTAS.has(c.nombre));
  const [orden, setOrden] = useState<{ columna: string; asc: boolean } | null>(null);

  const filas = useMemo(() => {
    if (!orden) return conjunto.filas;
    const tipo = columnas.find((c) => c.nombre === orden.columna)?.tipo ?? '';
    return [...conjunto.filas].sort((a, b) => {
      const x = claveOrden(a[orden.columna], tipo);
      const y = claveOrden(b[orden.columna], tipo);
      return (x < y ? -1 : x > y ? 1 : 0) * (orden.asc ? 1 : -1);
    });
  }, [conjunto.filas, orden, columnas]);

  const celda = (f: Fila, nombre: string, tipo: string) => {
    const v = f[nombre];
    const opciones = etiquetasValores ? opcionesDeColumna(nombre, etiquetasValores) : undefined;
    const texto = typeof v === 'string' && opciones?.has(v) ? opciones.get(v)! : formatear(v, tipo, nombre);
    const situacion = claseSituacion(nombre, v);
    if (situacion) return <span className={`estado-situacion ${situacion}`}>{texto}</span>;
    if (onAbrirClave && COLUMNAS_CLAVE.has(nombre) && typeof v === 'string' && ES_CLAVE_ISSUE.test(v)) {
      return (
        <button type="button" className="enlace" onClick={() => onAbrirClave(v)} title={`Ver el detalle de ${v}`}>
          {texto}
        </button>
      );
    }
    return <TextoLargo texto={texto} limite={COLUMNAS_TEXTO.has(nombre) ? 600 : 120} completo={COLUMNAS_TEXTO.has(nombre)} />;
  };

  const descargar = () => {
    const url = URL.createObjectURL(new Blob([aCsv(columnas, filas)], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${nombreArchivo}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const esFicha = permitirFicha && !accionesFila && conjunto.filas.length === 1 && columnas.length > 6;
  const encabezado = (
    <div className="encabezado-resultado">
      {titulo && <h3>{titulo}</h3>}
      {!esFicha && (
        <span className="contador">
          {conjunto.filas.length === 1 ? '1 registro' : `${conjunto.filas.length.toLocaleString('es-MX')} registros`}
        </span>
      )}
      {conjunto.filas.length > 0 && (
        <button type="button" className="boton secundario-btn" onClick={descargar}
                aria-label={titulo ? `Descargar CSV: ${titulo}` : undefined}>Descargar CSV</button>
      )}
    </div>
  );

  if (conjunto.filas.length === 0) {
    return (
      <section className="resultado">
        {encabezado}
        <p className="vacio">{textoVacio}</p>
      </section>
    );
  }

  if (esFicha) {
    const f = conjunto.filas[0];
    return (
      <section className="resultado">
        {encabezado}
        <dl className="ficha">
          {columnas.map((c) => (
            <div key={c.nombre}>
              <dt>{etiqueta(c.nombre)}</dt>
              <dd>{celda(f, c.nombre, c.tipo)}</dd>
            </div>
          ))}
        </dl>
      </section>
    );
  }

  return (
    <section className="resultado">
      {encabezado}
      {conjunto.truncado && (
        <p className="alerta">Se muestran solo los primeros {conjunto.filas.length.toLocaleString('es-MX')} registros. Use filtros más específicos.</p>
      )}
      <div className="contenedor-tabla">
        <table>
          <thead>
            <tr>
              {columnas.map((c) => {
                const activa = orden?.columna === c.nombre;
                return (
                  <th key={c.nombre} scope="col" className={esNumero(c.tipo) ? 'num' : undefined}
                      aria-sort={activa ? (orden!.asc ? 'ascending' : 'descending') : 'none'}>
                    <button type="button" onClick={() => setOrden({ columna: c.nombre, asc: activa ? !orden!.asc : true })}>
                      {ayudaColumnas?.[c.nombre] ? <abbr className="ayuda-columna" title={ayudaColumnas[c.nombre]}>{etiqueta(c.nombre)}</abbr> : etiqueta(c.nombre)}
                      <span className="orden" aria-hidden="true">{activa ? (orden!.asc ? '▲' : '▼') : ''}</span>
                    </button>
                  </th>
                );
              })}
              {accionesFila && <th scope="col" className="col-acciones">Acciones</th>}
            </tr>
          </thead>
          <tbody>
            {filas.map((f, i) => (
              <tr key={i}>
                {columnas.map((c) => (
                  <td key={c.nombre} className={[esNumero(c.tipo) ? 'num' : '', esDesviacion(c.nombre) && Number(f[c.nombre]) > 0 ? 'desviacion-positiva' : ''].join(' ').trim() || undefined}>{celda(f, c.nombre, c.tipo)}</td>
                ))}
                {accionesFila && <td className="col-acciones"><div className="acciones-fila">{accionesFila(f)}</div></td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/** Texto recortado con "Ver más" / "Ver menos" (antes solo se veía completo al pasar el ratón). */
function TextoLargo({ texto, limite, completo }: { texto: string; limite: number; completo: boolean }) {
  const [abierto, setAbierto] = useState(false);
  const largo = texto.length > limite;
  const visible = !largo || abierto ? texto : `${texto.slice(0, limite - 3).trimEnd()}…`;
  if (!largo && !completo) return <>{texto}</>;
  return (
    <span className={completo || abierto ? 'texto-largo completo' : 'texto-largo'}>
      {visible}
      {largo && (
        <>
          {' '}
          <button type="button" className="enlace ver-mas" aria-expanded={abierto} onClick={() => setAbierto((a) => !a)}>
            {abierto ? 'Ver menos' : 'Ver más'}
          </button>
        </>
      )}
    </span>
  );
}
