import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { reemplazar, valoresDeAccion } from '../acciones';
import { VistaProcedimiento } from '../componentes/VistaProcedimiento';
import type { AccionListado } from '../tipos';
import { parametro, procedimiento, simularFetch } from './datos';

const acciones: AccionListado[] = [
  { etiqueta: 'Nuevo rol', proc: 'Rol_Guardar', fila: false, exito: 'Rol {Nombre} creado.' },
  { etiqueta: 'Editar', proc: 'Rol_Guardar', fila: true, valores: { Nombre: '{Nombre}', Descripcion: '{Descripcion}' }, bloquear: ['Nombre'], exito: 'Rol {Nombre} guardado.' },
  { etiqueta: 'Eliminar', proc: 'Rol_Eliminar', fila: true, valores: { Nombre: '{Nombre}' }, directo: true, peligro: true,
    confirmar: '¿Eliminar el rol {Nombre}?', exito: 'Rol {Nombre} eliminado.', ocultarSi: { EsSistema: true } },
  { etiqueta: 'Sin permiso', proc: 'No_Concedido', fila: true },
];
const listado = procedimiento({ nombre: 'Roles_Listar', titulo: 'Roles', permiso: 'admin', acciones });
const guardar = procedimiento({ nombre: 'Rol_Guardar', titulo: 'Nuevo o editar rol', permiso: 'admin', accion: true, parametros: [
  parametro({ nombre: 'Nombre', tipo: 'nvarchar', opcional: false }), parametro({ nombre: 'Descripcion', tipo: 'nvarchar' }),
] });
const eliminar = procedimiento({ nombre: 'Rol_Eliminar', titulo: 'Eliminar rol', permiso: 'admin', accion: true, parametros: [
  parametro({ nombre: 'Nombre', tipo: 'nvarchar', opcional: false }),
] });
const roles = (lista: Record<string, unknown>[]) => ({ json: { resultados: [{ columnas: [
  { nombre: 'Nombre', tipo: 'nvarchar', nulo: false }, { nombre: 'Descripcion', tipo: 'nvarchar', nulo: true }, { nombre: 'EsSistema', tipo: 'bit', nulo: false },
], truncado: false, filas: lista }] } });

const vista = () => render(<VistaProcedimiento proc={listado} valoresUrl={{}} onNavegar={vi.fn()} puedeVerDetalle={false}
                                                onSyncPendiente={vi.fn()} catalogo={[listado, guardar, eliminar]} />);

describe('acciones de un listado (catálogos)', () => {
  it('plantillas: valores de la fila y mensajes', () => {
    expect(valoresDeAccion(acciones[1], { Nombre: 'Soporte', Descripcion: null })).toEqual({ Nombre: 'Soporte', Descripcion: '' });
    expect(valoresDeAccion({ etiqueta: 'x', fila: true, valores: { Activo: '{Activo}', Roles: 'Cliente' } }, { Activo: true }))
      .toEqual({ Activo: 'true', Roles: 'Cliente' });
    expect(reemplazar('¿Eliminar {Nombre}? Activo: {Activo}', { Nombre: 'Soporte', Activo: false })).toBe('¿Eliminar Soporte? Activo: No');
  });

  it('cada fila tiene sus acciones; las de roles del sistema y las no permitidas no aparecen', async () => {
    simularFetch({ 'POST /api/procedimientos/Roles_Listar': () => roles([
      { Nombre: 'Administrador', Descripcion: 'Todo', EsSistema: true }, { Nombre: 'Soporte', Descripcion: 'Mesa', EsSistema: false },
    ]) });
    vista();
    const admin = (await screen.findByText('Administrador')).closest('tr')!;
    const soporte = screen.getByText('Soporte').closest('tr')!;
    expect(within(admin).queryByRole('button', { name: 'Eliminar' })).not.toBeInTheDocument();
    expect(within(soporte).getByRole('button', { name: 'Eliminar' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Sin permiso' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '+ Nuevo rol' })).toBeInTheDocument();
  });

  it('Editar abre el formulario lleno con la llave bloqueada; al guardar avisa y actualiza el listado', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Roles_Listar': () => roles([{ Nombre: 'Soporte', Descripcion: 'Mesa', EsSistema: false }]),
      'POST /api/procedimientos/Rol_Guardar': () => ({ json: { resultados: [] } }),
    });
    vista();
    await userEvent.click(within((await screen.findByText('Soporte')).closest('tr')!).getByRole('button', { name: 'Editar' }));
    const dialogo = screen.getByRole('dialog', { name: 'Editar' });
    expect(within(dialogo).getByLabelText(/Nombre/)).toHaveAttribute('readonly');
    const desc = within(dialogo).getByLabelText(/Descripci/);
    expect(desc).toHaveValue('Mesa');
    await userEvent.clear(desc);
    await userEvent.type(desc, 'Mesa de ayuda N1');
    await userEvent.click(within(dialogo).getByRole('button', { name: 'Guardar' }));
    expect(await screen.findByText('Rol Soporte guardado.')).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(peticiones.find((p) => p.url.endsWith('/Rol_Guardar'))?.cuerpo).toEqual({ Nombre: 'Soporte', Descripcion: 'Mesa de ayuda N1' });
    expect(peticiones.filter((p) => p.url.endsWith('/Roles_Listar'))).toHaveLength(2);
  });

  it('Eliminar confirma, ejecuta sin formulario y actualiza el listado', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Roles_Listar': () => roles([{ Nombre: 'Soporte', Descripcion: 'Mesa', EsSistema: false }]),
      'POST /api/procedimientos/Rol_Eliminar': () => ({ json: { resultados: [] } }),
    });
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    vista();
    await userEvent.click(await screen.findByRole('button', { name: 'Eliminar' }));
    expect(confirmar).toHaveBeenCalledWith('¿Eliminar el rol Soporte?');
    expect(await screen.findByText('Rol Soporte eliminado.')).toBeInTheDocument();
    expect(peticiones.find((p) => p.url.endsWith('/Rol_Eliminar'))?.cuerpo).toEqual({ Nombre: 'Soporte' });
    await waitFor(() => expect(peticiones.filter((p) => p.url.endsWith('/Roles_Listar'))).toHaveLength(2));
  });

  it('Nuevo abre el formulario vacío; Escape lo cierra sin guardar', async () => {
    const peticiones = simularFetch({ 'POST /api/procedimientos/Roles_Listar': () => roles([]) });
    vista();
    await userEvent.click(await screen.findByRole('button', { name: '+ Nuevo rol' }));
    expect(within(screen.getByRole('dialog', { name: 'Nuevo rol' })).getByLabelText(/Nombre/)).toHaveValue('');
    await userEvent.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(peticiones.some((p) => p.url.endsWith('/Rol_Guardar'))).toBe(false);
  });
});
