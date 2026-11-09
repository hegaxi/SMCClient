import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { Formulario } from '../componentes/Formulario';
import type { ParametroInfo, ValoresFormulario } from '../tipos';
import { parametro, simularFetch } from './datos';

const filas = (lista: Record<string, unknown>[]) => ({ json: { resultados: [{ columnas: [], truncado: false, filas: lista }] } });

const roles = filas([
  { Nombre: 'Administrador', Descripcion: 'Todo' },
  { Nombre: 'Consulta', Descripcion: 'Todas las consultas' },
  { Nombre: 'Cliente', Descripcion: 'Clientes externos' },
]);

/** Formulario con estado, como lo usa VistaProcedimiento. */
function Probar({ parametros, onEnviar }: { parametros: ParametroInfo[]; onEnviar: (v: ValoresFormulario) => void }) {
  const [valores, setValores] = useState<ValoresFormulario>({});
  return (
    <Formulario parametros={parametros} valores={valores} errores={{}} ocupado={false} textoBoton="Guardar"
                onCambio={(n, v) => setValores((x) => ({ ...x, [n]: v }))} onEnviar={() => onEnviar(valores)} />
  );
}

describe('listas que salen de otro procedimiento (smc:origen)', () => {
  it('varios valores: casillas que se envían unidas con el separador', async () => {
    simularFetch({ 'POST /api/procedimientos/Roles_Listar': () => roles });
    const enviar = vi.fn();
    render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'Roles', tipo: 'nvarchar', opcional: false, multiple: ',',
      origen: { procedimiento: 'Roles_Listar', valor: 'Nombre', etiqueta: 'Nombre', descripcion: 'Descripcion', libre: false },
    })]} />);
    const grupo = await screen.findByRole('group', { name: /Roles/ });
    expect(grupo).toHaveTextContent('Todas las consultas');
    await userEvent.click(screen.getByRole('checkbox', { name: /Consulta/ }));
    await userEvent.click(screen.getByRole('checkbox', { name: /Cliente/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Guardar' }));
    expect(enviar).toHaveBeenLastCalledWith({ Roles: 'Consulta,Cliente' });
  });

  it('un valor: lista desplegable con clave y descripción', async () => {
    simularFetch({ 'POST /api/procedimientos/Proyectos_Listar': () => filas([
      { Clave: 'SMC26', Nombre: 'Mesa de Servicio' }, { Clave: 'SSM26', Nombre: 'Scrum SIAMCO' },
    ]) });
    const enviar = vi.fn();
    render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'Proyecto', tipo: 'varchar',
      origen: { procedimiento: 'Proyectos_Listar', valor: 'Clave', etiqueta: 'Clave', descripcion: 'Nombre', libre: false },
    })]} />);
    const lista = await screen.findByRole('combobox', { name: 'Proyecto' });
    await waitFor(() => expect(screen.getByRole('option', { name: 'SSM26 — Scrum SIAMCO' })).toBeInTheDocument());
    await userEvent.selectOptions(lista, 'SSM26');
    await userEvent.click(screen.getByRole('button', { name: 'Guardar' }));
    expect(enviar).toHaveBeenLastCalledWith({ Proyecto: 'SSM26' });
  });

  it('obligatorio con una sola opción: se elige sola', async () => {
    simularFetch({ 'POST /api/procedimientos/Sync_Estado': () => filas([{ Fuente: 'smco' }, { Fuente: 'smco' }]) });
    const enviar = vi.fn();
    render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'Fuente', tipo: 'varchar', opcional: false,
      origen: { procedimiento: 'Sync_Estado', valor: 'Fuente', etiqueta: null, descripcion: null, libre: false },
    })]} />);
    await waitFor(() => expect(screen.getByRole('combobox', { name: /Fuente/ })).toHaveValue('smco'));
  });

  it('sin permiso para la lista: vuelve a ser un campo de texto', async () => {
    simularFetch({ 'POST /api/procedimientos/Roles_Listar': () => ({ estado: 403, json: { title: 'Sin permiso', codigo: 'procedimiento.sin_permiso' } }) });
    const enviar = vi.fn();
    render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'Rol', tipo: 'nvarchar',
      origen: { procedimiento: 'Roles_Listar', valor: 'Nombre', etiqueta: null, descripcion: null, libre: false },
    })]} />);
    await userEvent.type(await screen.findByRole('textbox', { name: 'Rol' }), 'Consulta');
    await userEvent.click(screen.getByRole('button', { name: 'Guardar' }));
    expect(enviar).toHaveBeenLastCalledWith({ Rol: 'Consulta' });
  });

  it('libre: se elige de las sugerencias o se escribe un valor nuevo', async () => {
    simularFetch({ 'POST /api/procedimientos/Roles_Listar': () => roles });
    const enviar = vi.fn();
    render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'Nombre', tipo: 'nvarchar', opcional: false,
      origen: { procedimiento: 'Roles_Listar', valor: 'Nombre', etiqueta: 'Nombre', descripcion: 'Descripcion', libre: true },
    })]} />);
    await waitFor(() => expect(screen.getByRole('combobox', { name: /Nombre/ }).tagName).toBe('INPUT'));
    const campo = screen.getByRole('combobox', { name: /Nombre/ });
    await userEvent.click(campo);
    expect(screen.getAllByRole('option')).toHaveLength(3);
    await userEvent.type(campo, 'Soporte');
    expect(screen.getByText('Nuevo: se usará lo que escribió.')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Guardar' }));
    expect(enviar).toHaveBeenLastCalledWith({ Nombre: 'Soporte' });
  });

  it('lista larga: se busca escribiendo y se elige con el teclado; envía el valor (id), muestra la etiqueta', async () => {
    const personas = Array.from({ length: 20 }, (_, i) => ({ AccountId: `acc-${i}`, Nombre: `Persona ${i}`, Detalle: `${i} issues` }));
    simularFetch({ 'POST /api/procedimientos/Personas_Listar': () => filas(personas) });
    const enviar = vi.fn();
    render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'ResponsableId', tipo: 'varchar',
      origen: { procedimiento: 'Personas_Listar', valor: 'AccountId', etiqueta: 'Nombre', descripcion: 'Detalle', libre: false },
    })]} />);
    await waitFor(() => expect(screen.getByRole('combobox', { name: /Responsable/ }).tagName).toBe('INPUT'));
    const campo = screen.getByRole('combobox', { name: /Responsable/ });
    await userEvent.type(campo, 'Persona 1');
    expect(screen.getAllByRole('option').length).toBe(11); // Persona 1 y Persona 10..19
    await userEvent.keyboard('{ArrowDown}{Enter}');
    expect(campo).toHaveValue('Persona 10');
    await userEvent.click(screen.getByRole('button', { name: 'Guardar' }));
    expect(enviar).toHaveBeenLastCalledWith({ ResponsableId: 'acc-10' });
  });

  it('lista dependiente: los sprints se piden con el proyecto elegido', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Proyectos_Listar': () => filas([{ Clave: 'SSM26', Nombre: 'Scrum' }, { Clave: 'SMC26', Nombre: 'Mesa' }]),
      'POST /api/procedimientos/Sprints_Listar': (c) => filas((c as { Proyecto?: string }).Proyecto === 'SSM26'
        ? [{ Valor: 'Sprint 6', Etiqueta: 'Sprint 6', Detalle: 'SSM26 · activo' }]
        : [{ Valor: 'Sprint 6', Etiqueta: 'Sprint 6', Detalle: 'SSM26' }, { Valor: 'Sprint 9', Etiqueta: 'Sprint 9', Detalle: 'SSMCO' }]),
    });
    render(<Probar onEnviar={vi.fn()} parametros={[
      parametro({ nombre: 'Proyecto', tipo: 'varchar', origen: { procedimiento: 'Proyectos_Listar', valor: 'Clave', etiqueta: 'Clave', descripcion: 'Nombre', libre: false } }),
      parametro({ nombre: 'Sprint', tipo: 'nvarchar', origen: { procedimiento: 'Sprints_Listar', valor: 'Valor', etiqueta: 'Etiqueta', descripcion: 'Detalle', libre: false, parametros: { Proyecto: '@Proyecto' } } }),
    ]} />);
    await waitFor(() => expect(screen.getByRole('option', { name: 'Sprint 9 — SSMCO' })).toBeInTheDocument());
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Proyecto' }), 'SSM26');
    await waitFor(() => expect(screen.queryByRole('option', { name: 'Sprint 9 — SSMCO' })).not.toBeInTheDocument());
    expect(peticiones.filter((p) => p.url.endsWith('/Sprints_Listar')).map((p) => p.cuerpo)).toEqual([{}, { Proyecto: 'SSM26' }]);
  });
});
