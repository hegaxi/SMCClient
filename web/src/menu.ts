import type { ProcedimientoInfo } from './tipos';

/**
 * Organización del menú. Sale del catálogo de la API: cada procedimiento declara en la base su sección y subgrupo
 * (smc:menu), su posición (smc:orden) y, si es una acción de un listado, el listado del que cuelga (smc:padre); ver
 * db/11_DatosSemilla/091_Menu.sql. Uno sin smc:menu aparece igual, en "Otras consultas" o en Administración.
 * SUBGRUPOS_* y subagrupar los usa la pantalla "Permisos por opción", que agrupa por categoría de permiso.
 */
export interface SubgrupoMenu {
  titulo: string | null;
  procs: ProcedimientoInfo[];
  /** Sub-opciones (smc:padre) de cada procedimiento de procs, por nombre: p. ej. las acciones de un listado. */
  hijos?: Record<string, ProcedimientoInfo[]>;
}

export interface GrupoMenu {
  titulo: string;
  subgrupos: SubgrupoMenu[];
}

export type Regla = [RegExp, string];

export const SUBGRUPOS_CONSULTAS: Regla[] = [
  [/^(Issues?|Proyectos)_/, 'Historias y tickets'],
  [/^(Horas|Estimacion)_/, 'Tiempo y estimación'],
  [/^(Sprints?|Epicas?)_/, 'Avance de sprints y épicas'],
  [/^Sla_/, 'Mesa de ayuda (SLA)'],
];
export const SUBGRUPOS_ADMIN: Regla[] = [
  [/^(Usuarios?|Roles?|Organizaciones|Usuario|Permisos)_/, 'Usuarios y acceso'],
  [/^(Sync|Mapeos?|Mapeo|Campos)_/, 'Sincronización y campos'],
  [/^(Avisos?|Auditoria)_/, 'Monitoreo'],
  [/^ConsultaPersonalizada/, 'Consultas personalizadas'],
];

/** Subgrupo en el que cae un procedimiento (en el orden de las reglas; si ninguna aplica, el último). */
export function subagrupar(procs: ProcedimientoInfo[], reglas: Regla[], otros: string): SubgrupoMenu[] {
  const titulos = [...reglas.map(([, t]) => t), otros];
  const porTitulo = new Map<string, ProcedimientoInfo[]>(titulos.map((t) => [t, []]));
  for (const p of procs) porTitulo.get(reglas.find(([re]) => re.test(p.nombre))?.[1] ?? otros)!.push(p);
  return titulos.map((titulo) => ({ titulo, procs: ordenar(porTitulo.get(titulo)!) })).filter((s) => s.procs.length > 0);
}

/** Primero lo que se consulta, después lo que modifica (acciones); cada parte en orden alfabético. */
export function ordenar(procs: ProcedimientoInfo[]): ProcedimientoInfo[] {
  return [...procs].sort((a, b) => Number(a.accion) - Number(b.accion) || a.titulo.localeCompare(b.titulo, 'es'));
}

/** Sección y subgrupo cuando el procedimiento no declara smc:menu (uno nuevo aparece igual, sin tocar la interfaz). */
function ubicacionPorOmision(p: ProcedimientoInfo): string {
  return p.permiso === 'lectura' && !p.exentoSync ? 'Otras consultas' : 'Administración/Otras herramientas';
}

const SIN_ORDEN = 1_000_000;
const ordenDe = (p: ProcedimientoInfo) => p.orden ?? SIN_ORDEN;
/** Por smc:orden; sin orden, los listados antes que las acciones y luego por título. */
const comparar = (a: ProcedimientoInfo, b: ProcedimientoInfo) =>
  ordenDe(a) - ordenDe(b) || Number(a.accion) - Number(b.accion) || a.titulo.localeCompare(b.titulo, 'es');

export function agruparMenu(todos: ProcedimientoInfo[]): GrupoMenu[] {
  // El catálogo ya trae solo lo que el usuario tiene concedido. Tableros, filtros y consultas personalizadas
  // ("usuario") tienen pantallas propias, y lo de la sesión no es una opción del menú.
  const lista = todos.filter((p) => !p.oculto && p.permiso !== 'usuario' && p.permiso !== 'sesion');
  const visibles = new Set(lista.map((p) => p.nombre));
  // Las sub-opciones (smc:padre) cuelgan de su listado; si el usuario no ve el listado, aparecen solas.
  const esHijo = (p: ProcedimientoInfo) => !!p.padre && p.padre !== p.nombre && visibles.has(p.padre);

  const secciones = new Map<string, Map<string | null, ProcedimientoInfo[]>>();
  for (const p of lista.filter((x) => !esHijo(x))) {
    const [seccion, subgrupo] = (p.menu?.trim() || ubicacionPorOmision(p)).split('/', 2).map((x) => x.trim());
    if (!secciones.has(seccion)) secciones.set(seccion, new Map());
    const subs = secciones.get(seccion)!;
    const clave = subgrupo || null;
    if (!subs.has(clave)) subs.set(clave, []);
    subs.get(clave)!.push(p);
  }
  const hijosDe = (nombre: string) => lista.filter((x) => esHijo(x) && x.padre === nombre).sort(comparar);
  const minimo = (procs: ProcedimientoInfo[]) => Math.min(...procs.map(ordenDe));

  const grupos = [...secciones].map(([titulo, subs]) => {
    const subgrupos: SubgrupoMenu[] = [...subs].map(([t, procs]) => {
      const ordenados = procs.sort(comparar);
      return {
        titulo: t,
        procs: ordenados,
        hijos: Object.fromEntries(ordenados.map((p) => [p.nombre, hijosDe(p.nombre)]).filter(([, h]) => h.length > 0)),
      };
    }).sort((a, b) => minimo(a.procs) - minimo(b.procs));
    return { titulo, subgrupos, orden: Math.min(...subgrupos.map((s) => minimo(s.procs))) };
  });
  // Administración siempre al final, aunque alguna opción suya no declare orden.
  const peso = (g: { titulo: string; orden: number }) => (g.titulo === SECCION_ADMIN ? Number.MAX_SAFE_INTEGER : g.orden);
  return grupos.sort((a, b) => peso(a) - peso(b)).map(({ titulo, subgrupos }) => ({ titulo, subgrupos }));
}

export const SECCION_ADMIN = 'Administración';

/** "Administración › Usuarios y acceso" para el procedimiento indicado (migas de pan). */
export function ubicacion(grupos: GrupoMenu[], nombre: string): string[] {
  for (const g of grupos)
    for (const s of g.subgrupos)
      if (s.procs.some((p) => p.nombre === nombre || s.hijos?.[p.nombre]?.some((h) => h.nombre === nombre)))
        return s.titulo ? [g.titulo, s.titulo] : [g.titulo];
  return [];
}
