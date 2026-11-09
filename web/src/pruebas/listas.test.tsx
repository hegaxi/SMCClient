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
    const { container } = render(<Probar onEnviar={enviar} parametros={[parametro({
      nombre: 'Nombre', tipo: 'nvarchar', opcional: false,
      origen: { procedimiento: 'Roles_Listar', valor: 'Nombre', etiqueta: 'Nombre', descripcion: 'Descripcion', libre: true },
    })]} />);
    await waitFor(() => expect(container.querySelectorAll('datalist option')).toHaveLength(3));
    await userEvent.type(screen.getByRole('combobox', { name: /Nombre/ }), 'Soporte');
    await userEvent.click(screen.getByRole('button', { name: 'Guardar' }));
    expect(enviar).toHaveBeenLastCalledWith({ Nombre: 'Soporte' });
  });
});
