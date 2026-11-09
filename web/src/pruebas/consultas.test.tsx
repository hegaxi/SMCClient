import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../App';
import { ConsultaPersonalizadaVista } from '../componentes/ConsultaPersonalizadaVista';
import { procedimiento, simularFetch } from './datos';

const conjunto = (filas: Record<string, unknown>[]) => ({ salida: {}, resultados: [{ truncado: false, filas,
  columnas: ['Clave', 'Resumen', 'Organizacion', 'TotalFilas'].map((n) => ({ nombre: n, tipo: n === 'TotalFilas' ? 'int' : 'nvarchar', nulo: true })) }] });

const obtener = (admin: boolean) => ({ json: { salida: {}, resultados: [
  { columnas: [], truncado: false, filas: [{ ConsultaId: 7, Nombre: 'Tickets de mesa', Descripcion: 'Abiertos por organización',
    Criterios: '[{"campo":"estado","operador":"no_en","valores":["Done"]}]', Columnas: 'resumen,organizacion', OrdenarPor: null, Descendente: true,
    CompartidaCon: admin ? 'rol:Cliente' : null, PuedoEditar: admin, SoloMiOrganizacion: !admin }] },
  { columnas: [], truncado: false, filas: [
    { Clave: 'clave', Etiqueta: 'Clave', Tipo: 'texto', Alias: 'Clave', Multivalor: false },
    { Clave: 'resumen', Etiqueta: 'Resumen', Tipo: 'texto', Alias: 'Resumen', Multivalor: false },
    { Clave: 'organizacion', Etiqueta: 'Organización (cliente)', Tipo: 'lista', Alias: 'Organizacion', Multivalor: true },
    { Clave: 'estado', Etiqueta: 'Estado', Tipo: 'lista', Alias: 'Estado', Multivalor: false }] },
] } });

describe('Consultas personalizadas', () => {
  it('muestra los criterios, ordena en el servidor y el administrador la puede editar', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/ConsultaPersonalizada_Obtener': () => obtener(true),
      'POST /api/procedimientos/ConsultaPersonalizada_Ejecutar': () => ({ json: conjunto([{ Clave: 'MDA-50', Resumen: 'Falla', Organizacion: 'ACME', TotalFilas: 1 }]) }),
    });
    const navegar = vi.fn();
    render(<ConsultaPersonalizadaVista consultaId={7} onNavegar={navegar} puedeVerDetalle onSyncPendiente={() => {}} onEliminada={() => {}} />);

    expect(await screen.findByRole('heading', { name: 'Tickets de mesa' })).toBeInTheDocument();
    expect(within(screen.getByRole('list', { name: 'Criterios de la consulta' })).getByText('Estado: no Done')).toBeInTheDocument();
    expect(screen.getByText('Compartida con: rol:Cliente')).toBeInTheDocument();
    expect(await screen.findByText('1–1 de 1 issues')).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: 'Organización (cliente)' })).toBeInTheDocument();   // multivalor: no ordenable

    await userEvent.click(screen.getByRole('button', { name: 'Resumen' }));
    const ultima = () => peticiones.filter((p) => p.url.endsWith('/ConsultaPersonalizada_Ejecutar')).at(-1)!.cuerpo;
    await waitFor(() => expect(ultima()).toEqual({ ConsultaId: 7, Pagina: 1, TamanoPagina: 50, OrdenarPor: 'resumen', Descendente: false }));

    await userEvent.click(screen.getByRole('button', { name: 'Editar en búsqueda avanzada' }));
    expect(navegar).toHaveBeenLastCalledWith('Issues_Consultar', {
      ConsultaId: '7', Criterios: '[{"campo":"estado","operador":"no_en","valores":["Done"]}]', Columnas: 'resumen,organizacion' });
  });

  it('un cliente solo ve sus consultas personalizadas (sin reportes internos ni "Sincronizar ahora")', async () => {
    simularFetch({
      'GET /api/sesion': () => ({ json: { usuario: 'cliente1', nombre: 'Cliente ACME', roles: 'Cliente', esAdministrador: false, debeCambiarContrasena: false } }),
      'GET /api/procedimientos': () => ({ json: [
        procedimiento({ nombre: 'Sync_Estado', permiso: 'usuario', exentoSync: true, titulo: 'Estado de la sincronización' }),
        procedimiento({ nombre: 'ConsultasPersonalizadas_Listar', permiso: 'usuario', oculto: true }),
        procedimiento({ nombre: 'ConsultaPersonalizada_Ejecutar', permiso: 'usuario', oculto: true }),
      ] }),
      'POST /api/procedimientos/Sync_Resumen': () => ({ json: { salida: {}, resultados: [{ columnas: [], truncado: false,
        filas: [{ Fuente: 'smco', DatosVigentes: true, DatosAtrasados: false, UltimaSincronizacion: '2026-11-08T10:00:00-06:00', AvisosAbiertos: 0 }] }] } }),
      'POST /api/procedimientos/ConsultasPersonalizadas_Listar': () => ({ json: { salida: {}, resultados: [{ columnas: [], truncado: false,
        filas: [{ ConsultaId: 7, Nombre: 'Tickets de mesa', Descripcion: 'Abiertos por organización', PuedoEditar: false }] }] } }),
      'POST /api/procedimientos/ConsultaPersonalizada_Obtener': () => obtener(false),
      'POST /api/procedimientos/ConsultaPersonalizada_Ejecutar': () => ({ json: conjunto([{ Clave: 'MDA-50', Resumen: 'Falla', Organizacion: 'ACME', TotalFilas: 1 }]) }),
    });
    render(<App intervaloSyncMs={50} />);

    const menu = await screen.findByRole('navigation', { name: 'Consultas' });
    await within(menu).findByRole('link', { name: 'Tickets de mesa' });
    expect(within(menu).queryByRole('link', { name: 'Estado de la sincronización' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Sincronizar ahora' })).not.toBeInTheDocument();
    expect(within(menu).queryByRole('heading', { name: 'Administración' })).not.toBeInTheDocument();

    await userEvent.click(within(menu).getByRole('link', { name: 'Tickets de mesa' }));
    expect(await screen.findByText('Se muestran solo los tickets de su organización.')).toBeInTheDocument();
    expect(await screen.findByRole('cell', { name: 'MDA-50' })).toBeInTheDocument();   // sin enlace al detalle interno
    expect(screen.queryByRole('button', { name: 'Editar en búsqueda avanzada' })).not.toBeInTheDocument();
  });
});
