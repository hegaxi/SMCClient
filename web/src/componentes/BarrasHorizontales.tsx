import { useState } from 'react';
import type { Barra } from '../widgets';
import { formatoIndicador } from '../widgets';

interface Props {
  barras: Barra[];
  titulo: string;
  nombreValor: string;
  /** Porcentaje del total en el tooltip (solo tiene sentido en conteos y sumas). */
  porcentaje?: boolean;
}

/**
 * Barras horizontales de una sola serie (magnitud): un solo color, sin leyenda (el título dice qué se mide),
 * barras de 16 px con el extremo de datos redondeado, etiquetas en tinta de texto y tooltip al pasar o enfocar.
 */
export function BarrasHorizontales({ barras, titulo, nombreValor, porcentaje = true }: Props) {
  const [activa, setActiva] = useState<number | null>(null);
  const maximo = Math.max(...barras.map((b) => b.valor), 0);
  const total = barras.reduce((a, b) => a + b.valor, 0);
  if (barras.length === 0) return <p className="vacio">No hay datos con este filtro.</p>;

  return (
    <ul className="barras" aria-label={titulo}>
      {barras.map((b, i) => {
        const ancho = maximo > 0 ? Math.max(0, (b.valor / maximo) * 100) : 0;
        const detalle = `${b.etiqueta}: ${formatoIndicador(b.valor)} ${nombreValor.toLowerCase()}${porcentaje && total > 0 ? ` (${Math.round((b.valor / total) * 100)} %)` : ''}${b.agrupa ? ` · agrupa ${b.agrupa}` : ''}`;
        return (
          <li key={b.etiqueta} className="barras-fila" tabIndex={0} aria-label={detalle}
              onMouseEnter={() => setActiva(i)} onMouseLeave={() => setActiva(null)} onFocus={() => setActiva(i)} onBlur={() => setActiva(null)}>
            <span className="barras-etiqueta" title={b.etiqueta}>{b.etiqueta}</span>
            <span className="barras-pista">
              {b.valor > 0 && <span className="barras-barra" style={{ width: `${ancho}%` }} />}
            </span>
            <span className="barras-valor">{formatoIndicador(b.valor)}</span>
            {activa === i && <span className="barras-tooltip" role="tooltip">{detalle}</span>}
          </li>
        );
      })}
    </ul>
  );
}
