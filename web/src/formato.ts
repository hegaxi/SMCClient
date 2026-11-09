import type { ParametroInfo, ValoresFormulario } from './tipos';

const ENTEROS = new Set(['tinyint', 'smallint', 'int', 'bigint']);
const DECIMALES = new Set(['decimal', 'numeric', 'money', 'smallmoney', 'float', 'real']);
const FECHAS_HORA = new Set(['datetime', 'datetime2', 'smalldatetime', 'datetimeoffset']);

export const esNumero = (tipo: string) => ENTEROS.has(tipo) || DECIMALES.has(tipo);

// Los nombres técnicos (columnas, parámetros) no llevan acentos; se corrigen al mostrarlos.
const ACENTOS: Record<string, string> = {
  automaticas: 'automáticas', automatico: 'automático', atribucion: 'atribución', categoria: 'categoría',
  metodo: 'método', pagina: 'página', tamano: 'tamaño', resolucion: 'resolución', ultima: 'última',
  ultimo: 'último', minutos: 'minutos', sincronizacion: 'sincronización', descripcion: 'descripción',
  informacion: 'información', numero: 'número', solicitud: 'solicitud', vencimiento: 'vencimiento',
  dias: 'días', cuarentena: 'cuarentena', fecha: 'fecha', intento: 'intento',
  estimacion: 'estimación', desviacion: 'desviación', epica: 'épica', epicas: 'épicas', situacion: 'situación',
  jerarquia: 'jerarquía', automaticos: 'automáticos', subtareas: 'subtareas',
  antiguedad: 'antigüedad', max: 'máx.', min: 'min', id: 'ID', ok: 'OK', organizacion: 'organización', periodo: 'periodo',
  comentarios: 'comentarios', ultimos: 'últimos', ultimas: 'últimas', pais: 'país', titulo: 'título', codigo: 'código',
};

/** "HorasAutomaticas" -> "Horas automáticas"; "ProyectoClave" -> "Proyecto clave". */
export function etiqueta(nombre: string): string {
  const separado = nombre
    .replace(/_/g, ' ')
    .replace(/([a-záéíóúñ0-9])([A-ZÁÉÍÓÚÑ])/g, '$1 $2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2')
    .toLowerCase()
    .split(' ')
    .map((p) => ACENTOS[p] ?? p)
    .join(' ');
  return separado.charAt(0).toUpperCase() + separado.slice(1);
}

/**
 * Etiquetas para los valores de una columna, tomadas de las opciones (smc:opciones) de los parámetros de los
 * procedimientos: la columna TipoProyecto usa las opciones del parámetro TipoProyecto ("service_desk" -> "Mesa de ayuda");
 * CategoriaEstado, las de Categoria.
 */
export function etiquetasDeValores(procs: { parametros: ParametroInfo[] }[]): Map<string, Map<string, string>> {
  const porParametro = new Map<string, Map<string, string>>();
  for (const p of procs)
    for (const par of p.parametros)
      if (par.opciones?.length && !porParametro.has(par.nombre))
        porParametro.set(par.nombre, new Map(par.opciones.map((o) => [o.valor, o.etiqueta])));
  return porParametro;
}

export function opcionesDeColumna(columna: string, etiquetas: Map<string, Map<string, string>>): Map<string, string> | undefined {
  if (etiquetas.has(columna)) return etiquetas.get(columna);
  for (const [parametro, mapa] of etiquetas) if (columna.startsWith(parametro)) return mapa;
  return undefined;
}

const numero = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });
const fechaHora = new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' });

/** Texto para mostrar un valor de una columna según su tipo de SQL Server. */
export function formatear(valor: unknown, tipo: string): string {
  if (valor === null || valor === undefined || valor === '') return '—';
  if (tipo === 'bit') return valor ? 'Sí' : 'No';
  if (esNumero(tipo) && typeof valor === 'number') return numero.format(valor);
  if (tipo === 'date' && typeof valor === 'string') {
    // "2026-11-05T00:00:00": se muestra la fecha sin convertir zona horaria.
    const [a, m, d] = valor.slice(0, 10).split('-');
    return `${d}/${m}/${a}`;
  }
  if (FECHAS_HORA.has(tipo) && typeof valor === 'string') {
    const f = new Date(valor);
    return Number.isNaN(f.getTime()) ? valor : fechaHora.format(f);
  }
  if (typeof valor === 'object') return JSON.stringify(valor);
  if (typeof valor === 'string' && valor.startsWith('{"type":"doc"')) return adfATexto(valor) ?? valor;
  return String(valor);
}

/**
 * Documento de Jira en Atlassian Document Format (descripciones, campos de texto enriquecido) a texto legible:
 * párrafos y elementos de lista en líneas, menciones y emojis con su texto. null si no se puede leer.
 */
export function adfATexto(json: string): string | null {
  type Nodo = { type?: string; text?: string; attrs?: Record<string, unknown>; content?: Nodo[] };
  const BLOQUES = new Set(['paragraph', 'heading', 'listItem', 'blockquote', 'codeBlock', 'tableRow', 'rule']);
  const recorrer = (n: Nodo): string => {
    if (n.type === 'text') return n.text ?? '';
    if (n.type === 'hardBreak') return '\n';
    if (n.type === 'mention' || n.type === 'emoji' || n.type === 'status' || n.type === 'date')
      return String(n.attrs?.text ?? n.attrs?.shortName ?? '');
    const interior = (n.content ?? []).map(recorrer).join(n.type === 'tableRow' ? ' | ' : '');
    return BLOQUES.has(n.type ?? '') ? `${n.type === 'listItem' ? '• ' : ''}${interior}\n` : interior;
  };
  try {
    return recorrer(JSON.parse(json) as Nodo).replace(/\n{3,}/g, '\n\n').trim();
  } catch {
    return null;
  }
}

/** Valor para ordenar una columna. */
export function claveOrden(valor: unknown, tipo: string): number | string {
  if (valor === null || valor === undefined) return '';
  if (typeof valor === 'number') return valor;
  if (typeof valor === 'boolean') return valor ? 1 : 0;
  if ((FECHAS_HORA.has(tipo) || tipo === 'date') && typeof valor === 'string') return new Date(valor).getTime();
  return String(valor).toLocaleLowerCase('es-MX');
}

export type TipoControl = 'texto' | 'entero' | 'decimal' | 'fecha' | 'fechaHora' | 'siNo' | 'lista';

export function tipoControl(p: ParametroInfo): TipoControl {
  if (p.opciones?.length) return 'lista';
  if (p.tipo === 'bit') return 'siNo';
  if (ENTEROS.has(p.tipo)) return 'entero';
  if (DECIMALES.has(p.tipo)) return 'decimal';
  if (p.tipo === 'date') return 'fecha';
  if (FECHAS_HORA.has(p.tipo)) return 'fechaHora';
  return 'texto';
}

/**
 * Convierte lo que escribió el usuario al cuerpo JSON del POST. Los opcionales vacíos se omiten
 * (el procedimiento usa su valor por omisión); los obligatorios vacíos se dejan para que la API los reporte.
 */
export function construirCuerpo(parametros: ParametroInfo[], valores: ValoresFormulario): Record<string, unknown> {
  const cuerpo: Record<string, unknown> = {};
  for (const p of parametros) {
    if (p.salida) continue;
    const v = (valores[p.nombre] ?? '').trim();
    if (v === '') continue;
    switch (tipoControl(p)) {
      case 'entero':
      case 'decimal':
        cuerpo[p.nombre] = Number(v.replace(',', '.'));
        break;
      case 'siNo':
        cuerpo[p.nombre] = v === 'true';
        break;
      case 'fechaHora':
        // datetime-local no lleva zona: datetimeoffset se envía en UTC, los demás tal cual.
        cuerpo[p.nombre] = p.tipo === 'datetimeoffset' ? new Date(v).toISOString() : v;
        break;
      default:
        cuerpo[p.nombre] = v;
    }
  }
  return cuerpo;
}

/** Valores iniciales cómodos: periodo del mes en curso para parámetros de fecha obligatorios Desde/Hasta. */
export function valoresIniciales(parametros: ParametroInfo[], hoy = new Date()): ValoresFormulario {
  const iso = (f: Date) =>
    `${f.getFullYear()}-${String(f.getMonth() + 1).padStart(2, '0')}-${String(f.getDate()).padStart(2, '0')}`;
  const v: ValoresFormulario = {};
  for (const p of parametros) {
    if (p.tipo !== 'date' || p.opcional) continue;
    if (/^desde$/i.test(p.nombre)) v[p.nombre] = iso(new Date(hoy.getFullYear(), hoy.getMonth(), 1));
    if (/^hasta$/i.test(p.nombre)) v[p.nombre] = iso(hoy);
  }
  return v;
}

/** Convierte un conjunto de resultados a CSV (separador coma, UTF-8 con BOM para Excel). */
export function aCsv(columnas: { nombre: string }[], filas: Record<string, unknown>[]): string {
  const escapar = (v: unknown) => {
    if (v === null || v === undefined) return '';
    const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lineas = [columnas.map((c) => escapar(c.nombre)).join(',')];
  for (const f of filas) lineas.push(columnas.map((c) => escapar(f[c.nombre])).join(','));
  return '﻿' + lineas.join('\r\n');
}
