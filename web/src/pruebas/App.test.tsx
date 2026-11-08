import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../App';
import { parametro, procedimiento, simularFetch } from './datos';

const procs = [
  procedimiento({ nombre: 'Sync_Estado', exentoSync: true, titulo: 'Estado de la sincronización' }),
  procedimiento({ nombre: 'Sync_Solicitar', exentoSync: true, titulo: 'Sincronizar ahora', accion: true }),
  procedimiento({
    nombre: 'Issues_Buscar', titulo: 'Buscar historias y tickets', descripcion: 'Historias y tickets.',
    parametros: [parametro({ nombre: 'Proyecto', tipo: 'varchar', longitud: 50 })],
  }),
  procedimiento({ nombre: 'Issue_Detalle', titulo: 'Detalle de un issue', parametros: [parametro({ nombre: 'Clave', tipo: 'varchar', opcional: false })],
    titulosResultados: ['Datos del issue', 'Tiempo registrado'] }),
];

const estado = (vigentes: boolean) => ({
  json: {
    resultados: [
      { columnas: [], truncado: false, filas: [{ Fuente: 'smco', DatosVigentes: vigentes, UltimaSincronizacion: vigentes ? '2026-11-08T10:00:00-06:00' : null, AvisosAbiertos: 0 }] },
      { columnas: [], truncado: false, filas: [
        { Fuente: 'smco', Entidad: 'campo', Modo: 'catalogo', UltimaOk: '2026-11-08T10:00:00-06:00', UltimoEstado: 'ok' },
        { Fuente: 'smco', Entidad: 'issue', Modo: 'incremental', UltimaOk: null, UltimoEstado: vigentes ? 'ok' : 'corriendo' },
      ] },
    ],
  },
});

const issues = {
  json: {
    resultados: [{
      truncado: false,
      columnas: [{ nombre: 'Clave', tipo: 'varchar', nulo: true }, { nombre: 'Resumen', tipo: 'nvarchar', nulo: true }],
      filas: [{ Clave: 'MDA-1', Resumen: 'No puedo entrar' }],
    }],
  },
};

describe('App', () => {
  it('muestra la pantalla de sincronización hasta que los datos están vigentes', async () => {
    let vigentes = false;
    simularFetch({
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(vigentes),
    });
    render(<App intervaloSyncMs={50} />);

    expect(await screen.findByRole('heading', { name: 'Sincronizando los datos de Jira' })).toBeInTheDocument();
    expect(screen.getByText('Historias y tickets')).toBeInTheDocument();
    expect(screen.getByText('Sincronizando…')).toBeInTheDocument();

    vigentes = true;
    expect(await screen.findByRole('heading', { name: 'Scrum y mesa de ayuda' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Buscar historias y tickets' })).toBeInTheDocument();
  });

  it('abre una consulta, la ejecuta y guarda los filtros en la dirección; la clave abre el detalle', async () => {
    const peticiones = simularFetch({
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
      'POST /api/procedimientos/Issues_Buscar': () => issues,
      'POST /api/procedimientos/Issue_Detalle': () => ({ json: { resultados: [issues.json.resultados[0]] } }),
    });
    render(<App />);
    await userEvent.click(await screen.findByRole('link', { name: 'Buscar historias y tickets' }));
    expect(await screen.findByText('No puedo entrar')).toBeInTheDocument();   // corre sola al abrir

    await userEvent.type(screen.getByLabelText('Proyecto'), 'MDA');
    await userEvent.click(screen.getByRole('button', { name: 'Consultar' }));
    await waitFor(() => expect(peticiones.at(-1)?.cuerpo).toEqual({ Proyecto: 'MDA' }));
    expect(window.location.search).toBe('?Proyecto=MDA&p=Issues_Buscar');

    await userEvent.click(screen.getByRole('button', { name: 'MDA-1' }));
    expect(await screen.findByRole('heading', { name: 'Detalle de un issue' })).toBeInTheDocument();
    await waitFor(() => expect(peticiones.at(-1)).toEqual({ url: '/api/procedimientos/Issue_Detalle', cuerpo: { Clave: 'MDA-1' } }));
    expect(screen.getByRole('heading', { name: 'Datos del issue' })).toBeInTheDocument();
  });

  it('una acción no se ejecuta sola al abrirla', async () => {
    const peticiones = simularFetch({
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
    });
    render(<App />);
    await userEvent.click(await screen.findByRole('link', { name: 'Sincronizar ahora' }));
    expect(await screen.findByRole('button', { name: 'Ejecutar' })).toBeInTheDocument();
    expect(peticiones.some((p) => p.url.endsWith('/Sync_Solicitar'))).toBe(false);
  });

  it('si una consulta responde 503 vuelve a la pantalla de sincronización', async () => {
    let vigentes = true;
    simularFetch({
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(vigentes),
      'POST /api/procedimientos/Issues_Buscar': () => {
        vigentes = false;
        return { estado: 503, json: { title: 'Sincronizando', codigo: 'sync.pendiente' } };
      },
    });
    render(<App />);
    await userEvent.click(await screen.findByRole('link', { name: 'Buscar historias y tickets' }));
    expect(await screen.findByRole('heading', { name: 'Sincronizando los datos de Jira' })).toBeInTheDocument();
  });

  it('muestra los errores de validación de la API', async () => {
    simularFetch({
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
      'POST /api/procedimientos/Issue_Detalle': () => ({ estado: 400, json: { title: 'Hay parámetros faltantes o desconocidos.', errors: { Clave: ['Es obligatorio.'] } } }),
    });
    window.history.replaceState(null, '', '/?p=Issue_Detalle');
    render(<App />);
    await userEvent.click(await screen.findByRole('button', { name: 'Consultar' }));
    expect(await screen.findByText('Es obligatorio.')).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Hay parámetros faltantes o desconocidos.');
  });
});
