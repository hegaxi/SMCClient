import { describe, expect, it } from 'vitest';
import { agruparMenu, ubicacion } from '../menu';
import type { ProcedimientoInfo } from '../tipos';

const p = (nombre: string, permiso: string, extra: Partial<ProcedimientoInfo> = {}): ProcedimientoInfo => ({
  nombre, titulo: nombre.replace(/_/g, ' '), permiso, descripcion: null, exentoSync: false, parametros: [],
  columnas: null, titulosResultados: null, accion: false, oculto: false, ...extra,
});

const catalogo = [
  p('Issues_Buscar', 'lectura'),
  p('Horas_PorPersona', 'lectura'),
  p('Sla_Cumplimiento', 'lectura'),
  p('Nuevo_Reporte', 'lectura'),
  p('Issues_Campos', 'lectura', { oculto: true }),
  p('Sync_Estado', 'lectura', { exentoSync: true }),
  p('Mi_Usuario', 'sesion', { exentoSync: true }),
  p('Sync_Resumen', 'sesion', { exentoSync: true, oculto: true }),
  p('Permisos_Matriz', 'admin', { exentoSync: true }),
  p('Tablero_Guardar', 'usuario', { accion: true }),
  p('Usuario_Guardar', 'admin', { accion: true }),
  p('Usuarios_Listar', 'admin'),
  p('Auditoria_Listar', 'admin'),
];

const titulos = (grupos: ReturnType<typeof agruparMenu>) =>
  grupos.map((g) => [g.titulo, g.subgrupos.map((s) => [s.titulo, s.procs.map((x) => x.nombre)])]);

describe('agruparMenu', () => {
  it('agrupa por permiso y prefijo, con los listados antes que las acciones', () => {
    expect(titulos(agruparMenu(catalogo))).toEqual([
      ['Consultas', [
        ['Historias y tickets', ['Issues_Buscar']],
        ['Tiempo y estimación', ['Horas_PorPersona']],
        ['Mesa de ayuda (SLA)', ['Sla_Cumplimiento']],
        ['Otras consultas', ['Nuevo_Reporte']],
      ]],
      ['Sincronización', [[null, ['Sync_Estado']]]],
      ['Administración', [
        ['Usuarios y acceso', ['Permisos_Matriz', 'Usuarios_Listar', 'Usuario_Guardar']],
        ['Monitoreo', ['Auditoria_Listar']],
      ]],
    ]);
  });

  it('lo de la sesión y las pantallas propias (tableros, filtros) no son secciones del menú', () => {
    const cliente = catalogo.filter((x) => x.permiso === 'usuario' || x.permiso === 'sesion');
    expect(agruparMenu(cliente)).toEqual([]);
  });

  it('da la ubicación para las migas de pan', () => {
    const grupos = agruparMenu(catalogo);
    expect(ubicacion(grupos, 'Usuario_Guardar')).toEqual(['Administración', 'Usuarios y acceso']);
    expect(ubicacion(grupos, 'Sync_Estado')).toEqual(['Sincronización']);
    expect(ubicacion(grupos, 'No_Existe')).toEqual([]);
  });
});
