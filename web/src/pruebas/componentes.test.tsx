import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Formulario } from '../componentes/Formulario';
import { TablaResultados } from '../componentes/TablaResultados';
import { parametro } from './datos';

describe('Formulario', () => {
  const parametros = [
    parametro({ nombre: 'Desde', tipo: 'date', opcional: false, descripcion: 'Fecha inicial' }),
    parametro({ nombre: 'Proyecto', tipo: 'varchar', longitud: 50 }),
    parametro({ nombre: 'TipoProyecto', tipo: 'varchar', opciones: [{ valor: 'software', etiqueta: 'Scrum' }, { valor: 'service_desk', etiqueta: 'Mesa de ayuda' }] }),
    parametro({ nombre: 'Pagina', tipo: 'int' }),
  ];

  it('genera un control adecuado para cada parámetro', () => {
    render(<Formulario parametros={parametros} valores={{}} errores={{}} ocupado={false} onCambio={() => {}} onEnviar={() => {}} />);
    expect(screen.getByLabelText(/Desde/)).toHaveAttribute('type', 'date');
    expect(screen.getByLabelText(/Desde/)).toBeRequired();
    expect(screen.getByLabelText(/Desde/)).toHaveAccessibleDescription('Fecha inicial');
    expect(screen.getByLabelText('Proyecto')).toHaveAttribute('maxLength', '50');
    expect(within(screen.getByLabelText('Tipo proyecto')).getByRole('option', { name: 'Mesa de ayuda' })).toHaveValue('service_desk');
    expect(screen.getByLabelText('Página')).toHaveAttribute('type', 'number');
  });

  it('muestra los errores que devuelve la API junto a cada campo', () => {
    render(<Formulario parametros={parametros} valores={{}} errores={{ Desde: ['Es obligatorio.'] }} ocupado={false} onCambio={() => {}} onEnviar={() => {}} />);
    expect(screen.getByLabelText(/Desde/)).toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByText('Es obligatorio.')).toBeInTheDocument();
  });

  it('avisa los cambios y el envío', async () => {
    const cambios: [string, string][] = [];
    const enviar = vi.fn();
    render(<Formulario parametros={parametros} valores={{}} errores={{}} ocupado={false} onCambio={(n, v) => cambios.push([n, v])} onEnviar={enviar} />);
    await userEvent.type(screen.getByLabelText('Proyecto'), 'S');
    await userEvent.click(screen.getByRole('button', { name: 'Consultar' }));
    expect(cambios).toContainEqual(['Proyecto', 'S']);
    expect(enviar).toHaveBeenCalledOnce();
  });
});

describe('TablaResultados', () => {
  const conjunto = {
    truncado: false,
    columnas: [
      { nombre: 'Clave', tipo: 'varchar', nulo: true },
      { nombre: 'Horas', tipo: 'decimal', nulo: true },
      { nombre: 'TotalFilas', tipo: 'int', nulo: true },
    ],
    filas: [{ Clave: 'MDA-2', Horas: 3, TotalFilas: 2 }, { Clave: 'MDA-1', Horas: 10, TotalFilas: 2 }],
  };

  it('ordena por columna y oculta TotalFilas', async () => {
    render(<TablaResultados conjunto={conjunto} nombreArchivo="x" />);
    expect(screen.queryByRole('columnheader', { name: /Total filas/ })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Horas' }));
    await userEvent.click(screen.getByRole('button', { name: /Horas/ }));   // descendente
    const filas = screen.getAllByRole('row').slice(1);
    expect(within(filas[0]).getByText('MDA-1')).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: /Horas/ })).toHaveAttribute('aria-sort', 'descending');
  });

  it('las claves abren el detalle del issue', async () => {
    const abrir = vi.fn();
    render(<TablaResultados conjunto={conjunto} nombreArchivo="x" onAbrirClave={abrir} />);
    await userEvent.click(screen.getByRole('button', { name: 'MDA-1' }));
    expect(abrir).toHaveBeenCalledWith('MDA-1');
  });

  it('un solo registro con muchas columnas se muestra como ficha', () => {
    const columnas = Array.from({ length: 8 }, (_, i) => ({ nombre: `Dato${i}`, tipo: 'varchar', nulo: true }));
    const conjuntoUno = { truncado: false, columnas, filas: [Object.fromEntries(columnas.map((c) => [c.nombre, 'v']))] };
    const { unmount } = render(<TablaResultados conjunto={conjuntoUno} nombreArchivo="x" />);
    expect(screen.getByRole('table')).toBeInTheDocument();   // en una búsqueda sigue siendo tabla
    unmount();
    render(<TablaResultados conjunto={conjuntoUno} nombreArchivo="x" permitirFicha />);
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
    expect(screen.getByText('Dato7')).toBeInTheDocument();
  });

  it('sin filas muestra un mensaje', () => {
    render(<TablaResultados conjunto={{ ...conjunto, filas: [] }} nombreArchivo="x" />);
    expect(screen.getByText('No hay registros con estos filtros.')).toBeInTheDocument();
  });
});
