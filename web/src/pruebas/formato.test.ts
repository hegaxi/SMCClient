import { aCsv, construirCuerpo, etiqueta, etiquetasDeValores, formatear, opcionesDeColumna, valoresIniciales } from '../formato';
import { parametro } from './datos';

describe('formato', () => {
  it('convierte nombres de columna en etiquetas legibles', () => {
    expect(etiqueta('HorasRegistradas')).toBe('Horas registradas');
    expect(etiqueta('ProyectoClave')).toBe('Proyecto clave');
    expect(etiqueta('Sla')).toBe('Sla');
    expect(etiqueta('HorasAutomaticas')).toBe('Horas automáticas');
    expect(etiqueta('CategoriaEstado')).toBe('Categoría estado');
  });

  it('traduce valores codificados con las opciones de los parámetros', () => {
    const mapa = etiquetasDeValores([{ parametros: [
      parametro({ nombre: 'TipoProyecto', tipo: 'varchar', opciones: [{ valor: 'service_desk', etiqueta: 'Mesa de ayuda' }] }),
      parametro({ nombre: 'Categoria', tipo: 'varchar', opciones: [{ valor: 'done', etiqueta: 'Terminado' }] }),
    ] }]);
    expect(opcionesDeColumna('TipoProyecto', mapa)?.get('service_desk')).toBe('Mesa de ayuda');
    expect(opcionesDeColumna('CategoriaEstado', mapa)?.get('done')).toBe('Terminado');
    expect(opcionesDeColumna('Resumen', mapa)).toBeUndefined();
  });

  it('formatea según el tipo de SQL Server', () => {
    expect(formatear(null, 'int')).toBe('—');
    expect(formatear(true, 'bit')).toBe('Sí');
    expect(formatear('2026-11-05T00:00:00', 'date')).toBe('05/11/2026');   // sin correr la zona horaria
    expect(formatear(1234.5, 'decimal')).toBe('1,234.5');
  });

  it('arma el cuerpo con tipos y omite los opcionales vacíos', () => {
    const ps = [
      parametro({ nombre: 'Desde', tipo: 'date', opcional: false }),
      parametro({ nombre: 'Pagina', tipo: 'int' }),
      parametro({ nombre: 'Monto', tipo: 'decimal' }),
      parametro({ nombre: 'Activo', tipo: 'bit' }),
      parametro({ nombre: 'Proyecto', tipo: 'varchar' }),
    ];
    expect(construirCuerpo(ps, { Desde: '2026-10-01', Pagina: '2', Monto: '1,5', Activo: 'false', Proyecto: '  ' }))
      .toEqual({ Desde: '2026-10-01', Pagina: 2, Monto: 1.5, Activo: false });
  });

  it('propone el mes en curso para Desde/Hasta obligatorios', () => {
    const ps = [parametro({ nombre: 'Desde', tipo: 'date', opcional: false }), parametro({ nombre: 'Hasta', tipo: 'date', opcional: false })];
    expect(valoresIniciales(ps, new Date(2026, 10, 8))).toEqual({ Desde: '2026-11-01', Hasta: '2026-11-08' });
  });

  it('exporta CSV escapando comillas y comas', () => {
    expect(aCsv([{ nombre: 'A' }, { nombre: 'B' }], [{ A: 'x, "y"', B: null }])).toBe('﻿A,B\r\n"x, ""y""",');
  });
});
