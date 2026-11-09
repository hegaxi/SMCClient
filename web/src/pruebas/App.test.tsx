import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../App';
import { textoAtraso } from '../Principal';
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

const sesionLector = { json: { usuario: 'lector', nombre: 'Lector Uno', roles: 'Consulta', esAdministrador: false, debeCambiarContrasena: false } };
const sesionAdmin = { json: { usuario: 'admin', nombre: 'Admin', roles: 'Administrador', esAdministrador: true, debeCambiarContrasena: false } };

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
  it('con datos atrasados no bloquea: avisa y deja consultar', async () => {
    simularFetch({
      'GET /api/sesion': () => sesionLector,
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => ({ json: { resultados: [
        { columnas: [], truncado: false, filas: [{ Fuente: 'smco', DatosVigentes: true, DatosAtrasados: true, MinutosDesdeSincronizacion: 190,
          UltimaSincronizacion: '2026-11-08T07:00:00-06:00', AvisosAbiertos: 0 }] },
        { columnas: [], truncado: false, filas: [] },
      ] } }),
    });
    render(<App intervaloSyncMs={50} />);

    expect(await screen.findByRole('heading', { name: 'Scrum y mesa de ayuda' })).toBeInTheDocument();
    expect(screen.getByText(/Los datos de Jira tienen 3 horas sin actualizarse/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Buscar historias y tickets' })).toBeInTheDocument();
  });

  it('describe el atraso en minutos, horas o días', () => {
    expect(textoAtraso(45)).toBe('45 minutos');
    expect(textoAtraso(190)).toBe('3 horas');
    expect(textoAtraso(4000)).toBe('2 días');
  });

  it('muestra la pantalla de sincronización hasta que los datos están vigentes', async () => {
    let vigentes = false;
    simularFetch({
      'GET /api/sesion': () => sesionLector,
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
      'GET /api/sesion': () => sesionLector,
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
      'GET /api/sesion': () => sesionLector,
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
      'GET /api/sesion': () => sesionLector,
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
      'GET /api/sesion': () => sesionLector,
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

describe('Sesión', () => {
  it('pide iniciar sesión, envía el encabezado anti-CSRF y entra', async () => {
    const peticiones = simularFetch({
      'GET /api/sesion': () => ({ estado: 401, json: { codigo: 'sesion.requerida' } }),
      'POST /api/sesion/iniciar': (c) => ((c as { contrasena: string }).contrasena === 'correcta-123'
        ? sesionLector
        : { estado: 401, json: { title: 'Usuario o contraseña incorrectos, o la cuenta está bloqueada temporalmente por demasiados intentos.' } }),
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
    });
    render(<App />);
    await userEvent.type(await screen.findByLabelText('Usuario'), 'lector');
    await userEvent.type(screen.getByLabelText('Contraseña'), 'mala-123');
    await userEvent.click(screen.getByRole('button', { name: 'Iniciar sesión' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Usuario o contraseña incorrectos');
    expect(screen.getByLabelText('Contraseña')).toHaveValue('');

    await userEvent.type(screen.getByLabelText('Contraseña'), 'correcta-123');
    await userEvent.click(screen.getByRole('button', { name: 'Iniciar sesión' }));
    expect(await screen.findByText('Lector Uno')).toBeInTheDocument();
    expect(peticiones.filter((p) => p.url === '/api/sesion/iniciar').at(-1)?.cuerpo).toEqual({ usuario: 'lector', contrasena: 'correcta-123' });
    const llamada = (fetch as unknown as { mock: { calls: [string, RequestInit][] } }).mock.calls.find(([u]) => u === '/api/sesion/iniciar')!;
    expect((llamada[1].headers as Record<string, string>)['X-SMC-Solicitud']).toBe('1');
  });

  it('si debe cambiar su contraseña no deja pasar hasta cambiarla', async () => {
    let debeCambiar = true;
    const peticiones = simularFetch({
      'GET /api/sesion': () => ({ json: { ...sesionLector.json, debeCambiarContrasena: debeCambiar } }),
      'POST /api/sesion/cambiar-contrasena': () => { debeCambiar = false; return { estado: 204, json: null }; },
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
    });
    render(<App />);
    expect(await screen.findByRole('heading', { name: 'Establezca su contraseña' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Cancelar' })).not.toBeInTheDocument();
    await userEvent.type(screen.getByLabelText('Contraseña temporal'), 'temporal-123');
    await userEvent.type(screen.getByLabelText('Contraseña nueva'), 'Nueva-Clave-1');
    await userEvent.type(screen.getByLabelText('Repita la contraseña nueva'), 'Otra-Cosa-1');
    await userEvent.click(screen.getByRole('button', { name: 'Guardar contraseña' }));
    expect(screen.getByText('No coincide con la contraseña nueva.')).toBeInTheDocument();
    expect(peticiones.some((p) => p.url.endsWith('cambiar-contrasena'))).toBe(false);

    await userEvent.clear(screen.getByLabelText('Repita la contraseña nueva'));
    await userEvent.type(screen.getByLabelText('Repita la contraseña nueva'), 'Nueva-Clave-1');
    await userEvent.click(screen.getByRole('button', { name: 'Guardar contraseña' }));
    expect(await screen.findByRole('heading', { name: 'Scrum y mesa de ayuda' })).toBeInTheDocument();
  });

  it('cuando la sesión termina (401) vuelve al inicio de sesión con un aviso', async () => {
    simularFetch({
      'GET /api/sesion': () => sesionLector,
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
      'POST /api/procedimientos/Issues_Buscar': () => ({ estado: 401, json: { codigo: 'sesion.invalida' } }),
    });
    render(<App />);
    await userEvent.click(await screen.findByRole('link', { name: 'Buscar historias y tickets' }));
    expect(await screen.findByText('Su sesión terminó. Inicie sesión de nuevo.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Iniciar sesión' })).toBeInTheDocument();
  });

  it('el administrador ve Restablecer contraseña; Salir cierra la sesión', async () => {
    const peticiones = simularFetch({
      'GET /api/sesion': () => sesionAdmin,
      'GET /api/procedimientos': () => ({ json: [...procs, procedimiento({ nombre: 'Usuarios_Listar', permiso: 'admin', exentoSync: true, titulo: 'Usuarios' })] }),
      'POST /api/procedimientos/Sync_Estado': () => estado(true),
      'POST /api/procedimientos/Usuarios_Listar': () => ({ json: { resultados: [] } }),
      'POST /api/sesion/restablecer-contrasena': () => ({ estado: 204, json: null }),
      'POST /api/sesion/cerrar': () => ({ estado: 204, json: null }),
    });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<App />);
    await userEvent.click(await screen.findByRole('link', { name: 'Restablecer contraseña' }));
    await userEvent.type(screen.getByLabelText(/Usuario/), 'lector');
    await userEvent.click(screen.getByRole('button', { name: 'Restablecer' }));
    expect(await screen.findByRole('status')).toHaveTextContent('deberá cambiarla al entrar');
    expect((peticiones.find((p) => p.url.endsWith('restablecer-contrasena'))?.cuerpo as { usuario: string }).usuario).toBe('lector');

    await userEvent.click(screen.getByRole('button', { name: 'Salir' }));
    expect(await screen.findByRole('button', { name: 'Iniciar sesión' })).toBeInTheDocument();
  });
});
