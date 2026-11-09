import type { ProcedimientoInfo } from './tipos';

/**
 * Organización del menú. Sigue saliendo del catálogo de la API: cada procedimiento cae en una sección según su permiso
 * (lectura / usuario / admin) y, dentro de ella, en un subgrupo según el prefijo de su nombre. Un procedimiento nuevo con
 * un prefijo desconocido aparece igual, en el subgrupo "Otras…" de su sección: no hace falta tocar la interfaz.
 */
export interface SubgrupoMenu {
  titulo: string | null;
  procs: ProcedimientoInfo[];
}

export interface GrupoMenu {
  titulo: string;
  subgrupos: SubgrupoMenu[];
}

type Regla = [RegExp, string];

const SUBGRUPOS_CONSULTAS: Regla[] = [
  [/^(Issues?|Proyectos)_/, 'Historias y tickets'],
  [/^(Horas|Estimacion)_/, 'Tiempo y estimación'],
  [/^(Sprints?|Epicas?)_/, 'Avance de sprints y épicas'],
  [/^Sla_/, 'Mesa de ayuda (SLA)'],
];
const SUBGRUPOS_ADMIN: Regla[] = [
  [/^(Usuarios?|Roles?|Organizaciones|Usuario)_/, 'Usuarios y acceso'],
  [/^(Sync|Mapeos?|Mapeo|Campos)_/, 'Sincronización y campos'],
  [/^(Avisos?|Auditoria)_/, 'Monitoreo'],
  [/^ConsultaPersonalizada/, 'Consultas personalizadas'],
];

/** Subgrupo en el que cae un procedimiento (en el orden de las reglas; si ninguna aplica, el último). */
function subagrupar(procs: ProcedimientoInfo[], reglas: Regla[], otros: string): SubgrupoMenu[] {
  const titulos = [...reglas.map(([, t]) => t), otros];
  const porTitulo = new Map<string, ProcedimientoInfo[]>(titulos.map((t) => [t, []]));
  for (const p of procs) porTitulo.get(reglas.find(([re]) => re.test(p.nombre))?.[1] ?? otros)!.push(p);
  return titulos.map((titulo) => ({ titulo, procs: ordenar(porTitulo.get(titulo)!) })).filter((s) => s.procs.length > 0);
}

/** Primero lo que se consulta, después lo que modifica (acciones); cada parte en orden alfabético. */
export function ordenar(procs: ProcedimientoInfo[]): ProcedimientoInfo[] {
  return [...procs].sort((a, b) => Number(a.accion) - Number(b.accion) || a.titulo.localeCompare(b.titulo, 'es'));
}

export function agruparMenu(todos: ProcedimientoInfo[]): GrupoMenu[] {
  // Usuario interno: tiene alguna consulta de lectura (los clientes externos solo tienen las de "usuario").
  const interno = todos.some((p) => p.permiso === 'lectura');
  const lista = todos
    // De los de permiso "usuario" solo el estado de la sincronización va al menú (tableros y filtros tienen sus pantallas).
    .filter((p) => !p.oculto && (p.permiso !== 'usuario' || (interno && p.nombre.startsWith('Sync_'))));
  const consultas = lista.filter((p) => p.permiso === 'lectura' && !p.exentoSync);
  const sincronizacion = lista.filter((p) => (p.permiso === 'lectura' || p.permiso === 'usuario') && p.exentoSync);
  const admin = lista.filter((p) => p.permiso !== 'lectura' && p.permiso !== 'usuario');
  const grupos: GrupoMenu[] = [
    { titulo: 'Consultas', subgrupos: subagrupar(consultas, SUBGRUPOS_CONSULTAS, 'Otras consultas') },
    { titulo: 'Sincronización', subgrupos: [{ titulo: null, procs: ordenar(sincronizacion) }] },
    { titulo: 'Administración', subgrupos: subagrupar(admin, SUBGRUPOS_ADMIN, 'Otras herramientas') },
  ];
  return grupos.filter((g) => g.subgrupos.some((s) => s.procs.length > 0));
}

/** "Administración › Usuarios y acceso" para el procedimiento indicado (migas de pan). */
export function ubicacion(grupos: GrupoMenu[], nombre: string): string[] {
  for (const g of grupos)
    for (const s of g.subgrupos)
      if (s.procs.some((p) => p.nombre === nombre)) return s.titulo ? [g.titulo, s.titulo] : [g.titulo];
  return [];
}
