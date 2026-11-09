import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ArbolResultados, esArbol } from '../componentes/ArbolResultados';
import { ProyectosSync } from '../componentes/ProyectosSync';
import { TablaResultados } from '../componentes/TablaResultados';
import { adfATexto } from '../formato';
import type { ConjuntoResultados } from '../tipos';
import { simularFetch } from './datos';

const col = (nombre: string, tipo = 'nvarchar') => ({ nombre, tipo, nulo: true });

const arbol: ConjuntoResultados = {
  truncado: false,
  columnas: [col('Nodo'), col('PadreNodo'), col('Nivel', 'int'), col('Clave'), col('Elemento'), col('HorasRegistradas', 'decimal')],
  filas: [
    { Nodo: '#proyecto', PadreNodo: null, Nivel: 0, Clave: null, Elemento: 'SSM26 · Scrum', HorasRegistradas: 128 },
    { Nodo: 'SSM26-1', PadreNodo: '#proyecto', Nivel: 1, Clave: 'SSM26-1', Elemento: 'Épica uno', HorasRegistradas: 120 },
    { Nodo: 'SSM26-2', PadreNodo: 'SSM26-1', Nivel: 2, Clave: 'SSM26-2', Elemento: 'Tarea', HorasRegistradas: 120 },
    { Nodo: 'SSM26-3', PadreNodo: 'SSM26-2', Nivel: 3, Clave: 'SSM26-3', Elemento: 'Subtarea', HorasRegistradas: 40 },
    { Nodo: '#sin-epica', PadreNodo: '#proyecto', Nivel: 1, Clave: null, Elemento: '(Sin épica)', HorasRegistradas: 8 },
  ],
};

describe('árbol de resultados (Horas por proyecto)', () => {
  it('se reconoce por Nodo / PadreNodo / Nivel', () => {
    expect(esArbol(arbol)).toBe(true);
    expect(esArbol({ ...arbol, columnas: arbol.columnas.filter((c) => c.nombre !== 'PadreNodo') })).toBe(false);
  });

  it('abre con el proyecto y sus épicas; cada nivel se abre y la clave lleva al detalle', async () => {
    const abrir = vi.fn();
    render(<ArbolResultados conjunto={arbol} titulo="Épicas, tareas y subtareas" nombreArchivo="x" onAbrirClave={abrir} />);
    const tabla = screen.getByRole('treegrid');
    expect(within(tabla).getByText('Épica uno')).toBeInTheDocument();
    expect(within(tabla).getByText('(Sin épica)')).toBeInTheDocument();
    expect(within(tabla).queryByText('Tarea')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Abrir SSM26-1' }));
    expect(within(tabla).getByText('Tarea')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Abrir todo' }));
    expect(within(tabla).getByText('Subtarea')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'SSM26-3' }));
    expect(abrir).toHaveBeenCalledWith('SSM26-3');
    await userEvent.click(screen.getByRole('button', { name: 'Ver épicas' }));
    expect(within(tabla).queryByText('Tarea')).not.toBeInTheDocument();
  });
});

describe('Proyectos a sincronizar', () => {
  const lista = (sincronizaSmc22: boolean) => ({
    json: {
      resultados: [
        { columnas: [], truncado: false, filas: [
          { Fuente: 'smco', Clave: 'SMC22', Nombre: 'SIAMCO 22', TipoProyecto: 'service_desk', Sincronizar: sincronizaSmc22, Issues: 1065, Abiertos: 3 },
          { Fuente: 'smco', Clave: 'TSCA26', Nombre: 'Pruebas', TipoProyecto: 'service_desk', Sincronizar: false, Issues: 184, Motivo: 'Desactivado por admin' },
        ] },
        { columnas: [], truncado: false, filas: [{ NuevosSeSincronizan: true }] },
      ],
    },
  });

  it('desmarcar pide confirmación y desactiva el proyecto', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/ProyectosSync_Listar': () => lista(true),
      'POST /api/procedimientos/ProyectoSync_Establecer': () => lista(false),
    });
    const confirmar = vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<ProyectosSync />);
    expect(await screen.findByText('1 de 2 proyectos se sincronizan · 1,065 issues en reportes')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('checkbox', { name: 'Sincronizar SMC22' }));
    expect(confirmar).toHaveBeenCalled();
    expect(peticiones.at(-1)).toEqual({ url: '/api/procedimientos/ProyectoSync_Establecer', cuerpo: { Fuente: 'smco', Proyecto: 'SMC22', Sincronizar: false } });
    expect(await screen.findByText('SMC22 ya no se sincroniza y se ocultó de los reportes.')).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: 'Sincronizar SMC22' })).not.toBeChecked();
  });

  it('el filtro muestra solo los desactivados', async () => {
    simularFetch({ 'POST /api/procedimientos/ProyectosSync_Listar': () => lista(true) });
    render(<ProyectosSync />);
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: 'Mostrar' }), 'no');
    expect(screen.queryByRole('checkbox', { name: 'Sincronizar SMC22' })).not.toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: 'Sincronizar TSCA26' })).not.toBeChecked();
  });
});

describe('tablas: claves, texto largo y texto de Jira', () => {
  const conjunto: ConjuntoResultados = {
    truncado: false,
    columnas: [col('Clave'), col('Comentario')],
    filas: [
      { Clave: 'SMC26', Comentario: 'corto' },
      { Clave: 'SMC26-10', Comentario: `${'a'.repeat(700)} fin` },
    ],
  };

  it('solo una clave de issue abre el detalle; la de un proyecto no', () => {
    render(<TablaResultados conjunto={conjunto} nombreArchivo="x" onAbrirClave={() => {}} />);
    expect(screen.getByRole('button', { name: 'SMC26-10' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'SMC26' })).not.toBeInTheDocument();
  });

  it('un comentario largo se lee completo con "Ver más"', async () => {
    render(<TablaResultados conjunto={conjunto} nombreArchivo="x" />);
    expect(screen.queryByText(/ fin$/)).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Ver más' }));
    expect(screen.getByText(/ fin/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Ver menos' })).toHaveAttribute('aria-expanded', 'true');
  });

  it('el texto enriquecido de Jira (ADF) se muestra como texto', () => {
    const adf = JSON.stringify({ type: 'doc', version: 1, content: [
      { type: 'paragraph', content: [{ type: 'text', text: 'Se delimitan' }, { type: 'hardBreak' }, { type: 'text', text: 'las actividades' }] },
      { type: 'bulletList', content: [{ type: 'listItem', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'uno' }] }] }] },
    ] });
    expect(adfATexto(adf)).toBe('Se delimitan\nlas actividades\n• uno');
    expect(adfATexto('{"type":"doc", roto')).toBeNull();
  });
});
