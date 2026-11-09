import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { PermisosRoles } from '../componentes/PermisosRoles';
import { simularFetch } from './datos';

const tabla = (filas: Record<string, unknown>[]) => ({ columnas: [], truncado: false, filas });
const matriz = (concedidos: [string, string][]) => ({ json: { resultados: [
  tabla([
    { Rol: 'Administrador', EsExterno: false, EsSistema: true, UsuariosActivos: 1 },
    { Rol: 'Soporte', EsExterno: false, EsSistema: false, UsuariosActivos: 2 },
    { Rol: 'Cliente', EsExterno: true, EsSistema: false, UsuariosActivos: 0 },
  ]),
  tabla([
    { Codigo: 'tableros', Titulo: 'Tableros', Categoria: 'usuario', Principal: 'Tableros_Listar', EsAccion: false, ExentoSync: true, Procedimientos: 'Tableros_Listar' },
    { Codigo: 'consultas_personalizadas', Titulo: 'Consultas personalizadas', Categoria: 'usuario', Principal: 'ConsultasPersonalizadas_Listar', EsAccion: false, ExentoSync: false },
    { Codigo: 'api.Horas_PorPersona', Titulo: 'Horas por persona', Categoria: 'lectura', Principal: 'Horas_PorPersona', EsAccion: false, ExentoSync: false },
    { Codigo: 'api.Sla_EnRiesgo', Titulo: 'SLA por vencer', Categoria: 'lectura', Principal: 'Sla_EnRiesgo', EsAccion: false, ExentoSync: false },
    { Codigo: 'api.Sync_Estado', Titulo: 'Estado de la sincronización', Categoria: 'lectura', Principal: 'Sync_Estado', EsAccion: false, ExentoSync: true },
    { Codigo: 'contrasena.restablecer', Titulo: 'Restablecer contraseña', Categoria: 'admin', Principal: 'Usuario_RestablecerContrasena', EsAccion: true, ExentoSync: true },
    { Codigo: 'api.Usuarios_Listar', Titulo: 'Usuarios', Categoria: 'admin', Principal: 'Usuarios_Listar', EsAccion: false, ExentoSync: true },
    { Codigo: 'api.Auditoria_Listar', Titulo: 'Auditoría', Categoria: 'admin', Principal: 'Auditoria_Listar', EsAccion: false, ExentoSync: true },
  ]),
  tabla(concedidos.map(([Rol, Permiso]) => ({ Rol, Permiso }))),
] } });

describe('Permisos por opción', () => {
  it('muestra cada opción del menú por rol, agrupada como el menú', async () => {
    simularFetch({ 'POST /api/procedimientos/Permisos_Matriz': () => matriz([['Administrador', 'admin'], ['Administrador', 'lectura'], ['Soporte', 'api.Sla_EnRiesgo']]) });
    render(<PermisosRoles />);
    expect(await screen.findByRole('checkbox', { name: 'Soporte: SLA por vencer' })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'Soporte: Horas por persona' })).not.toBeChecked();
    for (const s of ['Tableros y consultas compartidas', 'Consultas', 'Sincronización', 'Administración'])
      expect(screen.getByRole('rowheader', { name: s })).toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Mesa de ayuda (SLA)' })).toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Usuarios y acceso' })).toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Monitoreo' })).toBeInTheDocument();
    // Lo que da una categoría completa se ve marcado y no se puede quitar suelto.
    const incluida = screen.getByRole('checkbox', { name: 'Administrador: Restablecer contraseña' });
    expect(incluida).toBeChecked();
    expect(incluida).toBeDisabled();
    // A un rol externo solo se le conceden tableros, filtros y consultas compartidas.
    expect(screen.getByRole('checkbox', { name: 'Cliente: Horas por persona' })).toBeDisabled();
    expect(screen.getByRole('checkbox', { name: 'Cliente: Consultas personalizadas' })).toBeEnabled();
  });

  it('una casilla concede o quita la opción al rol', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Permisos_Matriz': () => matriz([['Soporte', 'api.Sla_EnRiesgo']]),
      'POST /api/procedimientos/Rol_Opcion_Establecer': () => ({ json: { resultados: [] } }),
    });
    render(<PermisosRoles />);
    await userEvent.click(await screen.findByRole('checkbox', { name: 'Soporte: Restablecer contraseña' }));
    expect(await screen.findByRole('status')).toHaveTextContent('Soporte: se concedió "Restablecer contraseña"');
    expect(peticiones.at(-1)?.cuerpo).toEqual({ Rol: 'Soporte', Permiso: 'contrasena.restablecer', Concedido: true });
    expect(screen.getByRole('checkbox', { name: 'Soporte: Restablecer contraseña' })).toBeChecked();

    await userEvent.click(screen.getByRole('checkbox', { name: 'Soporte: SLA por vencer' }));
    await waitFor(() => expect(peticiones.at(-1)?.cuerpo).toEqual({ Rol: 'Soporte', Permiso: 'api.Sla_EnRiesgo', Concedido: false }));
    expect(screen.getByRole('checkbox', { name: 'Soporte: SLA por vencer' })).not.toBeChecked();
  });

  it('si la base rechaza el cambio lo explica y la casilla no cambia', async () => {
    simularFetch({
      'POST /api/procedimientos/Permisos_Matriz': () => matriz([['Administrador', 'admin']]),
      'POST /api/procedimientos/Rol_Opcion_Establecer': () => ({ estado: 409, json: { title: 'El rol Administrador debe conservar el permiso admin.' } }),
    });
    render(<PermisosRoles />);
    const fila = (await screen.findByRole('rowheader', { name: /Toda la administración/ })).closest('tr')!;
    await userEvent.click(within(fila).getByRole('checkbox', { name: 'Administrador: Toda la administración' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('debe conservar el permiso admin');
    expect(within(fila).getByRole('checkbox', { name: 'Administrador: Toda la administración' })).toBeChecked();
  });
});
