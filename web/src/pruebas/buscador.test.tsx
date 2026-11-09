import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { BuscadorIssues } from '../componentes/BuscadorIssues';
import { aParametros, columnasEfectivas, deParametros, describirCriterio, leerCampos, moverColumna, type EstadoBusqueda } from '../buscador';
import { parametro, procedimiento, simularFetch } from './datos';

const filasCampos = [
  { Clave: 'clave', Etiqueta: 'Clave', Tipo: 'texto', Origen: 'Jira', Multivalor: false, EsColumna: true, ColumnaPredeterminada: true, Operadores: 'contiene,no_contiene,igual,distinto,vacio,no_vacio', Alias: 'Clave' },
  { Clave: 'texto', Etiqueta: 'Texto', Tipo: 'texto', Origen: 'Jira', Multivalor: false, EsColumna: false, ColumnaPredeterminada: false, Operadores: 'contiene,no_contiene,igual,distinto,vacio,no_vacio', Alias: 'Texto' },
  { Clave: 'resumen', Etiqueta: 'Resumen', Tipo: 'texto', Origen: 'Jira', Multivalor: false, EsColumna: true, ColumnaPredeterminada: true, Operadores: 'contiene,no_contiene,igual,distinto,vacio,no_vacio', Alias: 'Resumen' },
  { Clave: 'estado', Etiqueta: 'Estado', Tipo: 'lista', Origen: 'Jira', Multivalor: false, EsColumna: true, ColumnaPredeterminada: true, Operadores: 'en,no_en,vacio,no_vacio', Alias: 'Estado' },
  { Clave: 'creado', Etiqueta: 'Creado', Tipo: 'fecha', Origen: 'Jira', Multivalor: false, EsColumna: true, ColumnaPredeterminada: false, Operadores: 'desde,hasta,entre,igual,vacio,no_vacio', Alias: 'Creado' },
  { Clave: 'horas', Etiqueta: 'Horas invertidas', Tipo: 'numero', Origen: 'Jira', Multivalor: false, EsColumna: true, ColumnaPredeterminada: false, Operadores: 'igual,distinto,mayor,mayor_igual,menor,menor_igual,entre,vacio,no_vacio', Alias: 'HorasInvertidas' },
  { Clave: 'etiquetas', Etiqueta: 'Etiquetas', Tipo: 'lista', Origen: 'Jira', Multivalor: true, EsColumna: true, ColumnaPredeterminada: false, Operadores: 'en,no_en,vacio,no_vacio', Alias: 'Etiquetas' },
  { Clave: 'cf:customfield_10468', Etiqueta: 'Estación', Tipo: 'lista', Origen: 'Personalizado', Multivalor: true, EsColumna: true, ColumnaPredeterminada: false, Operadores: 'en,no_en,vacio,no_vacio', Alias: 'Estación' },
];
const campos = leerCampos(filasCampos);
const vacio: EstadoBusqueda = { criterios: [], columnas: [], ordenarPor: 'actualizado', descendente: true, pagina: 1 };

describe('Estado de la búsqueda', () => {
  it('describe los criterios como los leería una persona', () => {
    const c = (clave: string) => campos.find((x) => x.clave === clave);
    expect(describirCriterio({ campo: 'estado', operador: 'no_en', valores: ['Done', 'Closed', 'Cancelado'] }, c('estado'))).toBe('Estado: no Done, Closed +1');
    expect(describirCriterio({ campo: 'creado', operador: 'desde', valor: '{inicio_mes}' }, c('creado'))).toBe('Creado: desde inicio del mes');
    expect(describirCriterio({ campo: 'creado', operador: 'entre', valor: '2026-10-01', hasta: '2026-10-31' }, c('creado'))).toBe('Creado: entre 01/10/2026 y 31/10/2026');
    expect(describirCriterio({ campo: 'horas', operador: 'vacio' }, c('horas'))).toBe('Horas invertidas: está vacío');
    expect(describirCriterio({ campo: 'estado', operador: 'en', valores: [] }, c('estado'))).toBe('Estado');
  });

  it('va y vuelve de la dirección sin perder nada; los criterios incompletos no se envían', () => {
    const e: EstadoBusqueda = {
      criterios: [
        { campo: 'estado', operador: 'en', valores: ['To Do'] },
        { campo: 'horas', operador: 'entre', valor: '2', hasta: '' },
        { campo: 'etiquetas', operador: 'vacio' },
      ],
      columnas: ['resumen', 'cf:customfield_10468'], ordenarPor: 'clave', descendente: false, pagina: 3,
    };
    const p = aParametros(e, campos);
    expect(JSON.parse(p.Criterios)).toEqual([{ campo: 'estado', operador: 'en', valores: ['To Do'] }, { campo: 'etiquetas', operador: 'vacio' }]);
    expect(p).toMatchObject({ Columnas: 'resumen,cf:customfield_10468', OrdenarPor: 'clave', Descendente: 'false', Pagina: '3' });
    const vuelta = deParametros(p);
    expect(vuelta.criterios).toHaveLength(2);
    expect(vuelta).toMatchObject({ columnas: ['resumen', 'cf:customfield_10468'], ordenarPor: 'clave', descendente: false, pagina: 3 });
    expect(aParametros(vacio, campos)).toEqual({});
    expect(deParametros({ Criterios: 'no es json' }).criterios).toEqual([]);
  });

  it('columnas: predeterminadas con la clave primero, y se reordenan', () => {
    expect(columnasEfectivas(vacio, campos)).toEqual(['clave', 'resumen', 'estado']);
    expect(columnasEfectivas({ ...vacio, columnas: ['estado', 'clave'] }, campos)).toEqual(['clave', 'estado']);
    expect(moverColumna(['clave', 'a', 'b'], 'b', -1)).toEqual(['clave', 'b', 'a']);
    expect(moverColumna(['clave', 'a'], 'a', 1)).toEqual(['clave', 'a']);
  });
});

describe('BuscadorIssues', () => {
  const proc = procedimiento({
    nombre: 'Issues_Consultar', titulo: 'Búsqueda avanzada',
    parametros: [parametro({ nombre: 'Criterios', tipo: 'nvarchar' }), parametro({ nombre: 'Columnas', tipo: 'nvarchar' }),
      parametro({ nombre: 'OrdenarPor', tipo: 'varchar' }), parametro({ nombre: 'Descendente', tipo: 'bit' }),
      parametro({ nombre: 'Pagina', tipo: 'int' }), parametro({ nombre: 'TamanoPagina', tipo: 'int' })],
  });
  const conjunto = (filas: Record<string, unknown>[], columnas = ['Clave', 'Resumen', 'Estado']) => ({
    resultados: [{ columnas: [...columnas, 'TotalFilas'].map((n) => ({ nombre: n, tipo: n === 'TotalFilas' ? 'int' : 'nvarchar', nulo: true })), truncado: false, filas }],
    salida: {},
  });

  it('agrega un criterio de lista, ordena por columna y navega al detalle', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Issues_Campos': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: filasCampos }], salida: {} } }),
      'POST /api/procedimientos/Issues_Valores': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [{ Valor: 'Done', Issues: 7 }, { Valor: 'To Do', Issues: 3 }] }], salida: {} } }),
      'POST /api/procedimientos/Issues_Consultar': () => ({ json: conjunto([{ Clave: 'MDA-1', Resumen: 'No entra', Estado: 'To Do', TotalFilas: 1 }]) }),
    });
    const navegar = vi.fn();
    render(<BuscadorIssues proc={proc} valoresUrl={{}} onNavegar={navegar} puedeVerDetalle puedeGuardarFiltro onSyncPendiente={() => {}} />);

    expect(await screen.findByText('1–1 de 1 issues')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /Estado: todos/ }));
    const editor = screen.getByRole('dialog', { name: 'Criterio: Estado' });
    await userEvent.click(await within(editor).findByRole('checkbox', { name: /To Do/ }));
    await userEvent.click(within(editor).getByRole('button', { name: 'Aplicar' }));

    await waitFor(() => expect(screen.getByRole('button', { name: /Estado: To Do/ })).toBeInTheDocument());
    const ultima = () => peticiones.filter((p) => p.url.endsWith('/Issues_Consultar')).at(-1)!.cuerpo as Record<string, unknown>;
    await waitFor(() => expect(JSON.parse(String(ultima().Criterios))).toEqual([{ campo: 'estado', operador: 'en', valores: ['To Do'] }]));
    expect(navegar).toHaveBeenLastCalledWith('Issues_Consultar', expect.objectContaining({ Criterios: expect.stringContaining('To Do') }), true);

    await userEvent.click(screen.getByRole('button', { name: 'Resumen' }));
    await waitFor(() => expect(ultima()).toMatchObject({ OrdenarPor: 'resumen', Descendente: false, Pagina: 1, TamanoPagina: 50 }));

    await userEvent.click(screen.getByRole('button', { name: 'MDA-1' }));
    expect(navegar).toHaveBeenLastCalledWith('Issue_Detalle', { Clave: 'MDA-1' });
  });

  it('criterio sobre un campo personalizado con "Más criterios", texto libre y columnas', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Issues_Campos': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: filasCampos }], salida: {} } }),
      'POST /api/procedimientos/Issues_Valores': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: [{ Valor: 'ESTACIÓN SUR', Issues: 2 }] }], salida: {} } }),
      'POST /api/procedimientos/Issues_Consultar': () => ({ json: conjunto([]) }),
    });
    render(<BuscadorIssues proc={proc} valoresUrl={{ Criterios: '[{"campo":"creado","operador":"desde","valor":"{inicio_anio}"}]' }}
                           onNavegar={() => {}} puedeVerDetalle={false} puedeGuardarFiltro={false} onSyncPendiente={() => {}} />);

    expect(await screen.findByRole('button', { name: /Creado: desde inicio del año/ })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: '+ Más criterios' }));
    await userEvent.type(screen.getByRole('searchbox', { name: 'Buscar campo' }), 'estac');
    await userEvent.click(screen.getByRole('button', { name: 'Estación' }));
    await userEvent.click(await screen.findByRole('checkbox', { name: /ESTACIÓN SUR/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Aplicar' }));

    await userEvent.type(screen.getByRole('searchbox', { name: 'Buscar texto' }), 'impresora{Enter}');
    const ultima = () => peticiones.filter((p) => p.url.endsWith('/Issues_Consultar')).at(-1)!.cuerpo as Record<string, unknown>;
    await waitFor(() => expect(JSON.parse(String(ultima().Criterios))).toEqual([
      { campo: 'texto', operador: 'contiene', valor: 'impresora' },
      { campo: 'creado', operador: 'desde', valor: '{inicio_anio}' },
      { campo: 'cf:customfield_10468', operador: 'en', valores: ['ESTACIÓN SUR'] },
    ]));
    expect(screen.getByText('No hay issues con estos criterios.')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Columnas' }));
    await userEvent.selectOptions(screen.getByLabelText('Agregar columna'), 'horas');
    await waitFor(() => expect(ultima().Columnas).toBe('clave,resumen,estado,horas'));
    await userEvent.click(screen.getByRole('button', { name: 'Subir Horas invertidas' }));
    await waitFor(() => expect(ultima().Columnas).toBe('clave,resumen,horas,estado'));
  });

  it('los errores de SQL (p. ej. campo eliminado de Jira) llegan al usuario', async () => {
    simularFetch({
      'POST /api/procedimientos/Issues_Campos': () => ({ json: { resultados: [{ columnas: [], truncado: false, filas: filasCampos }], salida: {} } }),
      'POST /api/procedimientos/Issues_Consultar': () => ({ estado: 400, json: { title: 'Campos desconocidos: cf:customfield_1.', codigo: 'sql.50400' } }),
    });
    render(<BuscadorIssues proc={proc} valoresUrl={{ Criterios: '[{"campo":"cf:customfield_1","operador":"vacio"}]' }}
                           onNavegar={() => {}} puedeVerDetalle={false} puedeGuardarFiltro={false} onSyncPendiente={() => {}} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Campos desconocidos: cf:customfield_1.');
    await userEvent.click(screen.getByRole('button', { name: /cf:customfield_1/ }));
    expect(screen.queryByRole('button', { name: /cf:customfield_1/ })).not.toBeInTheDocument();
  });
});
