import { render, screen, waitFor } from '@testing-library/react';
import { WidgetVista } from '../componentes/WidgetVista';
import { barrasDeResumen, parametrosResumen, usaResumen } from '../widgets';
import { simularFetch } from './datos';

describe('Widgets sobre una búsqueda avanzada', () => {
  it('barras e indicadores (salvo el conteo) se calculan en SQL', () => {
    expect(usaResumen('Issues_Consultar', 'barras', { etiqueta: 'estado', agregacion: 'conteo' })).toBe(true);
    expect(usaResumen('Issues_Consultar', 'indicador', { agregacion: 'suma', columna: 'horas' })).toBe(true);
    expect(usaResumen('Issues_Consultar', 'indicador', { agregacion: 'conteo' })).toBe(false);   // usa TotalFilas
    expect(usaResumen('Issues_Consultar', 'tabla', {})).toBe(false);
    expect(usaResumen('Horas_PorPersona', 'barras', { etiqueta: 'Persona', valor: 'Horas' })).toBe(false);
  });

  it('parámetros del resumen: criterios del filtro, campo, cálculo y número de barras', () => {
    const p = { Criterios: '[{"campo":"abierto","operador":"es","valor":"1"}]', Columnas: 'resumen', TamanoPagina: 500 };
    expect(parametrosResumen(p, 'barras', { etiqueta: 'estado', agregacion: 'conteo', limite: 8 }))
      .toEqual({ Criterios: p.Criterios, AgruparPor: 'estado', Top: 8, Agregacion: 'conteo' });
    expect(parametrosResumen(p, 'indicador', { agregacion: 'suma', columna: 'horas' }))
      .toEqual({ Criterios: p.Criterios, Agregacion: 'suma', Valor: 'horas' });
  });

  it('las barras llegan calculadas, con "Otros" y cuántos grupos agrupa', () => {
    expect(barrasDeResumen([
      { Grupo: 'Done', Valor: 900, EsOtros: false, Grupos: 1 },
      { Grupo: null, Valor: 12, EsOtros: false, Grupos: 1 },
      { Grupo: 'Otros', Valor: 40, EsOtros: true, Grupos: 6 },
    ])).toEqual([{ etiqueta: 'Done', valor: 900 }, { etiqueta: '(vacío)', valor: 12 }, { etiqueta: 'Otros', valor: 40, agrupa: 6 }]);
  });

  it('el widget pide el resumen a la base y no las filas', async () => {
    const peticiones = simularFetch({
      'POST /api/procedimientos/Issues_Resumir': () => ({ json: { salida: {}, resultados: [{ columnas: [], truncado: false, filas: [
        { Grupo: 'In Progress', Valor: 1250, Issues: 1250, Grupos: 1, EsOtros: false, EtiquetaGrupo: 'Estado', EtiquetaValor: null },
        { Grupo: 'Done', Valor: 830, Issues: 830, Grupos: 1, EsOtros: false, EtiquetaGrupo: 'Estado', EtiquetaValor: null },
      ] }] } }),
    });
    const widget = {
      WidgetId: 1, Titulo: 'Issues por estado', Filtro: 'Abiertos', Procedimiento: 'Issues_Consultar', Tipo: 'barras', Ancho: 2, PuedoEjecutar: true,
      Configuracion: '{"etiqueta":"estado","agregacion":"conteo","limite":10}', ParametrosResueltos: '{"Criterios":"[]","TamanoPagina":500}',
    };
    render(<WidgetVista widget={widget} edicion={false} primero ultimo onAbrirConsulta={() => {}} onSyncPendiente={() => {}}
                        onMover={() => {}} onEditar={() => {}} onQuitar={() => {}} />);
    expect(await screen.findByRole('list', { name: 'Issues por estado' })).toHaveTextContent('1,250');
    await waitFor(() => expect(peticiones).toHaveLength(1));
    expect(peticiones[0]).toEqual({ url: '/api/procedimientos/Issues_Resumir', cuerpo: { Criterios: '[]', AgruparPor: 'estado', Top: 10, Agregacion: 'conteo' } });
  });
});
