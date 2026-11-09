// Búsqueda avanzada de issues (api.Issues_Consultar): criterios, columnas y orden, como el navegador de Jira.
import { FECHAS_RELATIVAS } from './componentes/GuardarFiltro';
import type { Fila, ValoresFormulario } from './tipos';

export type TipoCampo = 'texto' | 'numero' | 'fecha' | 'lista' | 'usuario' | 'bit';
export type Operador =
  | 'en' | 'no_en' | 'contiene' | 'no_contiene' | 'igual' | 'distinto' | 'mayor' | 'mayor_igual' | 'menor' | 'menor_igual'
  | 'desde' | 'hasta' | 'entre' | 'es' | 'vacio' | 'no_vacio';

export interface CampoBuscador {
  clave: string;
  etiqueta: string;
  tipo: TipoCampo;
  origen: string;
  multivalor: boolean;
  esColumna: boolean;
  predeterminada: boolean;
  operadores: Operador[];
  alias: string;
}

export interface Criterio {
  campo: string;
  operador: Operador;
  valor?: string;
  hasta?: string;
  valores?: string[];
}

export interface EstadoBusqueda {
  criterios: Criterio[];
  /** Vacío = las columnas predeterminadas. */
  columnas: string[];
  ordenarPor: string;
  descendente: boolean;
  pagina: number;
}

/** Campos que se muestran siempre en la barra, como en Jira (si existen). */
export const CAMPOS_BASICOS = ['proyecto', 'tipo', 'estado', 'responsable'];
export const TAMANO_PAGINA = 50;

export const OPERADORES: Record<Operador, string> = {
  en: 'es alguno de', no_en: 'no es ninguno de', contiene: 'contiene', no_contiene: 'no contiene',
  igual: 'es igual a', distinto: 'es distinto de', mayor: 'mayor que', mayor_igual: 'mayor o igual que',
  menor: 'menor que', menor_igual: 'menor o igual que', desde: 'desde', hasta: 'hasta', entre: 'entre',
  es: 'es', vacio: 'está vacío', no_vacio: 'tiene valor',
};

export const sinValor = (op: Operador) => op === 'vacio' || op === 'no_vacio';
export const usaLista = (op: Operador) => op === 'en' || op === 'no_en';

export function leerCampos(filas: Fila[]): CampoBuscador[] {
  return filas.map((f) => ({
    clave: String(f.Clave),
    etiqueta: String(f.Etiqueta),
    tipo: String(f.Tipo) as TipoCampo,
    origen: String(f.Origen),
    multivalor: f.Multivalor === true,
    esColumna: f.EsColumna === true,
    predeterminada: f.ColumnaPredeterminada === true,
    operadores: String(f.Operadores).split(',') as Operador[],
    alias: String(f.Alias),
  }));
}

/** Operador con el que empieza un criterio nuevo. */
export function operadorInicial(c: CampoBuscador): Operador {
  return c.operadores.includes('en') ? 'en' : c.operadores.includes('contiene') ? 'contiene' : c.operadores.includes('desde') ? 'desde' : c.operadores[0];
}

/** ¿El criterio tiene lo necesario para aplicarse? (los incompletos no se envían). */
export function criterioCompleto(c: Criterio, campo?: CampoBuscador): boolean {
  if (sinValor(c.operador)) return true;
  if (usaLista(c.operador)) return (c.valores?.length ?? 0) > 0;
  if (!c.valor?.trim()) return false;
  if (c.operador === 'entre' && !c.hasta?.trim()) return false;
  if (campo?.tipo === 'numero') return !Number.isNaN(Number(c.valor)) && (c.operador !== 'entre' || !Number.isNaN(Number(c.hasta)));
  return true;
}

const textoFecha = (v?: string) => {
  if (!v) return '';
  const relativa = FECHAS_RELATIVAS.find((f) => f.valor === v);
  if (relativa) return relativa.etiqueta.toLowerCase();
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : v;
};

/** "Estado: no es Done, Closed" · "Creado: desde inicio del año" · "Horas: entre 2 y 4". */
export function describirCriterio(c: Criterio, campo?: CampoBuscador): string {
  const nombre = campo?.etiqueta ?? c.campo;
  if (!criterioCompleto(c, campo)) return nombre;
  if (sinValor(c.operador)) return `${nombre}: ${OPERADORES[c.operador]}`;
  if (usaLista(c.operador)) {
    const v = c.valores!;
    const lista = v.length > 2 ? `${v.slice(0, 2).join(', ')} +${v.length - 2}` : v.join(', ');
    return `${nombre}: ${c.operador === 'no_en' ? 'no ' : ''}${lista}`;
  }
  const f = campo?.tipo === 'fecha' ? textoFecha : (x?: string) => x ?? '';
  if (c.operador === 'es') return `${nombre}: ${c.valor === '1' ? 'sí' : 'no'}`;
  if (c.operador === 'entre') return `${nombre}: entre ${f(c.valor)} y ${f(c.hasta)}`;
  return `${nombre}: ${OPERADORES[c.operador]} ${f(c.valor)}`;
}

/** Cuerpo para api.Issues_Consultar (y para guardarlo como filtro). Los criterios incompletos no se envían. */
export function aParametros(e: EstadoBusqueda, campos: CampoBuscador[]): Record<string, string> {
  const criterios = e.criterios
    .filter((c) => criterioCompleto(c, campos.find((x) => x.clave === c.campo)))
    .map((c) => {
      if (sinValor(c.operador)) return { campo: c.campo, operador: c.operador };
      if (usaLista(c.operador)) return { campo: c.campo, operador: c.operador, valores: c.valores };
      return { campo: c.campo, operador: c.operador, valor: c.valor!.trim(), ...(c.operador === 'entre' ? { hasta: c.hasta!.trim() } : {}) };
    });
  const p: Record<string, string> = {};
  if (criterios.length) p.Criterios = JSON.stringify(criterios);
  if (e.columnas.length) p.Columnas = e.columnas.join(',');
  if (e.ordenarPor && e.ordenarPor !== 'actualizado') p.OrdenarPor = e.ordenarPor;
  if (!e.descendente) p.Descendente = 'false';
  if (e.pagina > 1) p.Pagina = String(e.pagina);
  return p;
}

/** Estado a partir de la dirección o de un filtro guardado (mismos nombres que los parámetros del procedimiento). */
export function deParametros(v: ValoresFormulario): EstadoBusqueda {
  let criterios: Criterio[] = [];
  try {
    const leidos: unknown = JSON.parse(v.Criterios ?? '[]');
    if (Array.isArray(leidos))
      criterios = leidos
        .filter((c): c is Criterio => typeof c === 'object' && c !== null && typeof (c as Criterio).campo === 'string' && typeof (c as Criterio).operador === 'string')
        .map((c) => ({
          campo: c.campo, operador: c.operador,
          ...(c.valor !== undefined ? { valor: String(c.valor) } : {}),
          ...(c.hasta !== undefined ? { hasta: String(c.hasta) } : {}),
          ...(Array.isArray(c.valores) ? { valores: c.valores.map(String) } : {}),
        }));
  } catch {
    // dirección editada a mano: se ignora
  }
  const pagina = Number(v.Pagina);
  return {
    criterios,
    columnas: (v.Columnas ?? '').split(',').map((x) => x.trim()).filter(Boolean),
    ordenarPor: v.OrdenarPor || 'actualizado',
    descendente: !/^(false|0)$/i.test(v.Descendente ?? ''),
    pagina: Number.isInteger(pagina) && pagina > 1 ? pagina : 1,
  };
}

/** Columnas efectivas (las elegidas o las predeterminadas), siempre con la clave primero. */
export function columnasEfectivas(e: EstadoBusqueda, campos: CampoBuscador[]): string[] {
  const elegidas = e.columnas.length ? e.columnas : campos.filter((c) => c.predeterminada).map((c) => c.clave);
  return ['clave', ...elegidas.filter((c) => c !== 'clave')];
}

/** Mueve una columna una posición (la clave no se mueve). */
export function moverColumna(columnas: string[], clave: string, delta: -1 | 1): string[] {
  const i = columnas.indexOf(clave);
  const j = i + delta;
  if (i < 0 || j < 0 || j >= columnas.length) return columnas;
  const r = [...columnas];
  [r[i], r[j]] = [r[j], r[i]];
  return r;
}
