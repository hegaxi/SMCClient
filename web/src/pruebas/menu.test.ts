import { describe, expect, it } from 'vitest';
import { agruparMenu, ubicacion } from '../menu';
import type { ProcedimientoInfo } from '../tipos';

const p = (nombre: string, permiso: string, extra: Partial<ProcedimientoInfo> = {}): ProcedimientoInfo => ({
  nombre, titulo: nombre.replace(/_/g, ' '), permiso, descripcion: null, exentoSync: false, parametros: [],
  columnas: null, titulosResultados: null, accion: false, oculto: false, ...extra,
});

// Como lo declara db/11_DatosSemilla/091_Menu.sql (smc:menu, smc:orden, smc:padre).
const catalogo = [
  p('Usuarios_Listar', 'admin', { menu: 'Administración/Usuarios y clientes', orden: 910 }),
  p('Usuario_Guardar', 'admin', { accion: true, menu: 'Administración/Usuarios y clientes', orden: 911, padre: 'Usuarios_Listar' }),
  p('Auditoria_Listar', 'admin', { menu: 'Administración/Monitoreo', orden: 985 }),
  p('Sla_Resumen', 'lectura', { menu: 'Mesa de ayuda', orden: 410 }),
  p('Issues_Buscar', 'lectura', { menu: 'Buscar', orden: 120 }),
  p('Issues_Consultar', 'lectura', { menu: 'Buscar', orden: 110 }),
  p('Horas_PorPersona', 'lectura', { menu: 'Tiempo', orden: 310 }),
  p('Nuevo_Reporte', 'lectura'),
  p('Nueva_Herramienta', 'admin'),
  p('Issue_Detalle', 'lectura', { oculto: true, menu: 'Buscar' }),
  p('Mi_Usuario', 'sesion', { exentoSync: true }),
  p('Tablero_Guardar', 'usuario', { accion: true }),
];

const titulos = (grupos: ReturnType<typeof agruparMenu>) =>
  grupos.map((g) => [g.titulo, g.subgrupos.map((s) => [s.titulo, s.procs.map((x) => x.nombre)])]);

describe('agruparMenu', () => {
  it('ordena secciones, subgrupos y opciones por smc:orden, con Administración al final', () => {
    expect(titulos(agruparMenu(catalogo))).toEqual([
      ['Buscar', [[null, ['Issues_Consultar', 'Issues_Buscar']]]],
      ['Tiempo', [[null, ['Horas_PorPersona']]]],
      ['Mesa de ayuda', [[null, ['Sla_Resumen']]]],
      ['Otras consultas', [[null, ['Nuevo_Reporte']]]],
      ['Administración', [
        ['Usuarios y clientes', ['Usuarios_Listar']],
        ['Monitoreo', ['Auditoria_Listar']],
        ['Otras herramientas', ['Nueva_Herramienta']],
      ]],
    ]);
  });

  it('las acciones (smc:padre) cuelgan de su listado', () => {
    const usuarios = agruparMenu(catalogo).find((g) => g.titulo === 'Administración')!.subgrupos[0];
    expect(usuarios.hijos?.Usuarios_Listar?.map((x) => x.nombre)).toEqual(['Usuario_Guardar']);
  });

  it('si no ve el listado, la acción aparece sola en su subgrupo', () => {
    const sinListado = catalogo.filter((x) => x.nombre !== 'Usuarios_Listar');
    const usuarios = agruparMenu(sinListado).find((g) => g.titulo === 'Administración')!.subgrupos[0];
    expect([usuarios.titulo, usuarios.procs.map((x) => x.nombre)]).toEqual(['Usuarios y clientes', ['Usuario_Guardar']]);
  });

  it('lo oculto, lo de la sesión y las pantallas propias (tableros, filtros) no son opciones del menú', () => {
    const nombres = agruparMenu(catalogo).flatMap((g) => g.subgrupos.flatMap((s) => s.procs.map((x) => x.nombre)));
    expect(nombres).not.toContain('Issue_Detalle');
    const cliente = catalogo.filter((x) => x.permiso === 'usuario' || x.permiso === 'sesion');
    expect(agruparMenu(cliente)).toEqual([]);
  });

  it('da la ubicación para las migas de pan, también de las sub-opciones', () => {
    const grupos = agruparMenu(catalogo);
    expect(ubicacion(grupos, 'Usuario_Guardar')).toEqual(['Administración', 'Usuarios y clientes']);
    expect(ubicacion(grupos, 'Issues_Buscar')).toEqual(['Buscar']);
    expect(ubicacion(grupos, 'No_Existe')).toEqual([]);
  });
});
