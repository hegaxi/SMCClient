import type { ConjuntoResultados, Fila } from './tipos';

export type TipoWidget = 'indicador' | 'tabla' | 'barras';

export interface ConfigWidget {
  columna?: string;
  agregacion?: 'suma' | 'promedio' | 'conteo' | 'maximo' | 'minimo' | 'primero';
  etiqueta?: string;
  valor?: string;
  limite?: number;
  columnas?: string[];
  resultado?: number;
}

export const AGREGACIONES: { valor: NonNullable<ConfigWidget['agregacion']>; etiqueta: string }[] = [
  { valor: 'conteo', etiqueta: 'Número de registros' },
  { valor: 'suma', etiqueta: 'Suma' },
  { valor: 'promedio', etiqueta: 'Promedio' },
  { valor: 'maximo', etiqueta: 'Máximo' },
  { valor: 'minimo', etiqueta: 'Mínimo' },
  { valor: 'primero', etiqueta: 'Valor del primer registro' },
];

export function leerConfig(json: unknown): ConfigWidget {
  if (typeof json !== 'string') return {};
  try {
    return JSON.parse(json) as ConfigWidget;
  } catch {
    return {};
  }
}

const numero = (v: unknown) => (typeof v === 'number' ? v : typeof v === 'string' && v.trim() !== '' && !Number.isNaN(Number(v)) ? Number(v) : null);

/**
 * Valor de un indicador. "conteo" usa TotalFilas cuando la consulta es paginada (Issues_Buscar), porque las filas
 * recibidas son solo una página.
 */
export function calcularIndicador(c: ConjuntoResultados, config: ConfigWidget): number | string | null {
  const agregacion = config.agregacion ?? 'conteo';
  if (agregacion === 'conteo') {
    const total = numero(c.filas[0]?.TotalFilas);
    return total ?? c.filas.length;
  }
  if (!config.columna) return null;
  if (agregacion === 'primero') return (c.filas[0]?.[config.columna] as number | string | undefined) ?? null;
  const valores = c.filas.map((f) => numero(f[config.columna!])).filter((v): v is number => v !== null);
  if (valores.length === 0) return null;
  switch (agregacion) {
    case 'suma': return valores.reduce((a, b) => a + b, 0);
    case 'promedio': return valores.reduce((a, b) => a + b, 0) / valores.length;
    case 'maximo': return Math.max(...valores);
    case 'minimo': return Math.min(...valores);
    default: return null;
  }
}

export interface Barra {
  etiqueta: string;
  valor: number;
  /** Cuántas categorías agrupa (solo "Otros"). */
  agrupa?: number;
}

/** Suma el valor por etiqueta (p. ej. horas de una persona en varios proyectos), ordena y agrupa el resto en "Otros". */
export function calcularBarras(filas: Fila[], config: ConfigWidget, textoEtiqueta: (v: unknown) => string = String): Barra[] {
  if (!config.etiqueta || !config.valor) return [];
  const suma = new Map<string, number>();
  for (const f of filas) {
    const v = numero(f[config.valor]);
    if (v === null) continue;
    const e = f[config.etiqueta] === null || f[config.etiqueta] === undefined ? '(vacío)' : textoEtiqueta(f[config.etiqueta]);
    suma.set(e, (suma.get(e) ?? 0) + v);
  }
  const ordenadas = [...suma.entries()].map(([etiqueta, valor]) => ({ etiqueta, valor })).sort((a, b) => b.valor - a.valor);
  const limite = Math.max(1, config.limite ?? 10);
  if (ordenadas.length <= limite) return ordenadas;
  const resto = ordenadas.slice(limite - 1);
  return [...ordenadas.slice(0, limite - 1), { etiqueta: 'Otros', valor: resto.reduce((a, b) => a + b.valor, 0), agrupa: resto.length }];
}

const compacto = new Intl.NumberFormat('es-MX', { notation: 'compact', maximumFractionDigits: 1 });
const completo = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });

/** 1,284 · 12.9 mil · 4.2 M (formato compacto desde 10 000). */
export function formatoIndicador(v: number | string | null): string {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'string') return v;
  return Math.abs(v) >= 10_000 ? compacto.format(v) : completo.format(v);
}
