import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../App';
import { BarrasHorizontales } from '../componentes/BarrasHorizontales';
import { calcularBarras, calcularIndicador, formatoIndicador } from '../widgets';
import { parametro, procedimiento, simularFetch } from './datos';

describe('Cálculos de widgets', () => {
  const c = (filas: Record<string, unknown>[]) => ({ columnas: [], truncado: false, filas });

  it('el indicador "conteo" usa TotalFilas en consultas paginadas', () => {
    expect(calcularIndicador(c([{ Clave: 'A', TotalFilas: 125 }, { Clave: 'B', TotalFilas: 125 }]), { agregacion: 'conteo' })).toBe(125);
    expect(calcularIndicador(c([{ Clave: 'A' }, { Clave: 'B' }]), {})).toBe(2);
  });

  it('suma, promedio, máximo y primer valor', () => {
    const d = c([{ Horas: 2 }, { Horas: 8 }, { Horas: null }]);
    expect(calcularIndicador(d, { agregacion: 'suma', columna: 'Horas' })).toBe(10);
    expect(calcularIndicador(d, { agregacion: 'promedio', columna: 'Horas' })).toBe(5);
    expect(calcularIndicador(d, { agregacion: 'maximo', columna: 'Horas' })).toBe(8);
    expect(calcularIndicador(d, { agregacion: 'primero', columna: 'Horas' })).toBe(2);
  });

  it('las barras suman por etiqueta, ordenan y agrupan el resto en "Otros"', () => {
    const filas = [
      { Persona: 'Ana', Horas: 5 }, { Persona: 'Ana', Horas: 3 }, { Persona: 'Luis', Horas: 6 },
      { Persona: 'Eva', Horas: 1 }, { Persona: 'Raúl', Horas: 2 },
    ];
    expect(calcularBarras(filas, { etiqueta: 'Persona', valor: 'Horas', limite: 3 })).toEqual([
      { etiqueta: 'Ana', valor: 8 }, { etiqueta: 'Luis', valor: 6 }, { etiqueta: 'Otros', valor: 3, agrupa: 2 },
    ]);
  });

  it('formato compacto desde 10 000', () => {
    expect(formatoIndicador(1284)).toBe('1,284');
    expect(formatoIndicador(12_900)).toMatch(/^12\.9\s?(mil|k)$/);
    expect(formatoIndicador(null)).toBe('—');
  });
});

describe('BarrasHorizontales', () => {
  it('ancho proporcional, valor en texto y tooltip al enfocar', async () => {
    render(<BarrasHorizontales titulo="Horas por persona" nombreValor="Horas" barras={[{ etiqueta: 'Ana', valor: 8 }, { etiqueta: 'Luis', valor: 2 }]} />);
    const lista = screen.getByRole('list', { name: 'Horas por persona' });
    const [ana, luis] = within(lista).getAllByRole('listitem');
    expect((ana.querySelector('.barras-barra') as HTMLElement).style.width).toBe('100%');
    expect((luis.querySelector('.barras-barra') as HTMLElement).style.width).toBe('25%');
    await userEvent.tab();
    expect(screen.getByRole('tooltip')).toHaveTextContent('Ana: 8 horas (80 %)');
  });
});

const estado = { json: { resultados: [
  { columnas: [], truncado: false, filas: [{ Fuente: 'smco', DatosVigentes: true, UltimaSincronizacion: '2026-11-08T10:00:00-06:00', AvisosAbiertos: 0 }] },
  { columnas: [], truncado: false, filas: [] },
] } };
const sesion = { json: { usuario: 'ana', nombre: 'Ana', roles: 'Consulta', esAdministrador: false, debeCambiarContrasena: false } };
const procs = [
  procedimiento({ nombre: 'Sync_Estado', exentoSync: true }),
  procedimiento({ nombre: 'Filtro_Guardar', permiso: 'usuario', accion: true }),
  procedimiento({ nombre: 'Filtros_Listar', permiso: 'usuario' }),
  procedimiento({ nombre: 'Tableros_Listar', permiso: 'usuario' }),
  procedimiento({ nombre: 'Tablero_Obtener', permiso: 'usuario' }),
  procedimiento({
    nombre: 'Horas_PorPersona', titulo: 'Horas por persona',
    parametros: [parametro({ nombre: 'Desde', tipo: 'date', opcional: false }), parametro({ nombre: 'Hasta', tipo: 'date', opcional: false })],
    columnas: [{ nombre: 'Persona', tipo: 'nvarchar(255)', nulo: true }, { nombre: 'HorasTotales', tipo: 'decimal(12,2)', nulo: true }],
  }),
];
const horas = { json: { resultados: [{ truncado: false, columnas: [{ nombre: 'Persona', tipo: 'nvarchar', nulo: true }, { nombre: 'HorasTotales', tipo: 'decimal', nulo: true }],
  filas: [{ Persona: 'Ana', HorasTotales: 10 }, { Persona: 'Luis', HorasTotales: 4 }] }] } };

describe('Filtros y tableros', () => {
  it('cada pantalla propia aparece solo con su opción: ver tableros no deja crearlos', async () => {
    simularFetch({
      'GET /api/sesion': () => sesion,
      'GET /api/procedimientos': () => ({ json: procs.filter((p) => p.nombre !== 'Filtros_Listar' && p.nombre !== 'Filtro_Guardar') }),
      'POST /api/procedimientos/Sync_Resumen': () => estado,
      'POST /api/procedimientos/Tableros_Listar': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [
        { TableroId: 3, Nombre: 'Equipo', EsMio: true, EsInicio: false },
      ] }] } }),
    });
    window.history.replaceState(null, '', '/?p=_tablero_nuevo');
    render(<App />);
    expect(await screen.findByRole('link', { name: 'Equipo' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: '+ Nuevo tablero' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Mis filtros' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Nuevo tablero' })).not.toBeInTheDocument();
    window.history.replaceState(null, '', '/');
  });

  it('con "Crear y editar tableros" y "Mis filtros" aparecen sus enlaces', async () => {
    simularFetch({
      'GET /api/sesion': () => sesion,
      'GET /api/procedimientos': () => ({ json: [...procs, procedimiento({ nombre: 'Tablero_Guardar', permiso: 'usuario', accion: true, oculto: true })] }),
      'POST /api/procedimientos/Sync_Resumen': () => estado,
      'POST /api/procedimientos/Tableros_Listar': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [] }] } }),
    });
    window.history.replaceState(null, '', '/');
    render(<App />);
    expect(await screen.findByRole('link', { name: '+ Nuevo tablero' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Mis filtros' })).toBeInTheDocument();
  });

  it('guarda la consulta como filtro con fecha relativa', async () => {
    const peticiones = simularFetch({
      'GET /api/sesion': () => sesion,
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Resumen': () => estado,
      'POST /api/procedimientos/Tableros_Listar': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [] }] } }),
      'POST /api/procedimientos/Horas_PorPersona': () => horas,
      'POST /api/procedimientos/Filtro_Guardar': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [{ FiltroId: 7 }] }] } }),
    });
    window.history.replaceState(null, '', '/?p=Horas_PorPersona&Desde=2026-11-01&Hasta=2026-11-08');
    render(<App />);
    await userEvent.click(await screen.findByRole('button', { name: 'Guardar como filtro' }));
    await userEvent.type(screen.getByLabelText(/Nombre del filtro/), 'Horas del mes');
    await userEvent.selectOptions(screen.getByLabelText('Desde'), 'Inicio del mes');
    await userEvent.selectOptions(screen.getByLabelText('Hasta'), 'Hoy');
    await userEvent.click(screen.getByLabelText(/Compartir con quienes/));
    await userEvent.click(screen.getByRole('button', { name: 'Guardar filtro' }));

    expect(await screen.findByText(/Filtro "Horas del mes" guardado/)).toBeInTheDocument();
    const guardado = peticiones.find((p) => p.url.endsWith('/Filtro_Guardar'))!.cuerpo as Record<string, unknown>;
    expect(guardado).toMatchObject({ Nombre: 'Horas del mes', Procedimiento: 'Horas_PorPersona', Compartido: true });
    expect(JSON.parse(String(guardado.Parametros))).toEqual({ Desde: '{inicio_mes}', Hasta: '{hoy}' });
  });

  it('el tablero de inicio se muestra al entrar y cada widget ejecuta su consulta', async () => {
    const peticiones = simularFetch({
      'GET /api/sesion': () => sesion,
      'GET /api/procedimientos': () => ({ json: procs }),
      'POST /api/procedimientos/Sync_Resumen': () => estado,
      'POST /api/procedimientos/Tableros_Listar': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [
        { TableroId: 3, Nombre: 'Equipo', EsMio: false, Propietario: 'Lector', EsInicio: true },
      ] }] } }),
      'POST /api/procedimientos/Tablero_Obtener': () => ({ json: { resultados: [
        { columnas: [], truncado: false, filas: [{ TableroId: 3, Nombre: 'Equipo', Descripcion: 'Horas del equipo', Propietario: 'Lector', EsMio: false, EsInicio: true }] },
        { columnas: [], truncado: false, filas: [
          { WidgetId: 1, Titulo: 'Total de horas', Tipo: 'indicador', Configuracion: '{"agregacion":"suma","columna":"HorasTotales"}', Ancho: 1,
            FiltroId: 7, Filtro: 'Horas del mes', Procedimiento: 'Horas_PorPersona', ParametrosResueltos: '{"Desde":"2026-11-01","Hasta":"2026-11-08"}', PuedoEjecutar: true },
          { WidgetId: 2, Titulo: 'Horas por persona', Tipo: 'barras', Configuracion: '{"etiqueta":"Persona","valor":"HorasTotales"}', Ancho: 3,
            FiltroId: 7, Filtro: 'Horas del mes', Procedimiento: 'Horas_PorPersona', ParametrosResueltos: '{"Desde":"2026-11-01","Hasta":"2026-11-08"}', PuedoEjecutar: true },
          { WidgetId: 3, Titulo: 'Usuarios', Tipo: 'tabla', Configuracion: '{}', Ancho: 2,
            FiltroId: 8, Filtro: 'Todos', Procedimiento: 'Usuarios_Listar', ParametrosResueltos: '{}', PuedoEjecutar: false },
        ] },
      ] } }),
      'POST /api/procedimientos/Horas_PorPersona': () => horas,
    });
    render(<App />);
    expect(await screen.findByRole('heading', { name: 'Equipo', level: 1 })).toBeInTheDocument();
    expect(screen.getByText('De Lector', { exact: false })).toBeInTheDocument();
    expect(await screen.findByText('14')).toBeInTheDocument();                                   // indicador: suma
    expect(await screen.findByRole('list', { name: 'Horas por persona' })).toBeInTheDocument();  // barras
    expect(screen.getByText('Sin permiso para esta consulta.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Editar' })).not.toBeInTheDocument();             // no es su tablero
    await waitFor(() => expect(peticiones.filter((p) => p.url.endsWith('/Horas_PorPersona')).length).toBe(2));
    expect(peticiones.find((p) => p.url.endsWith('/Horas_PorPersona'))!.cuerpo).toEqual({ Desde: '2026-11-01', Hasta: '2026-11-08' });
    expect(peticiones.some((p) => p.url.endsWith('/Usuarios_Listar'))).toBe(false);

    await userEvent.click(screen.getByRole('button', { name: 'Ver tabla' }));
    expect(screen.getByRole('table')).toBeInTheDocument();
  });
});
