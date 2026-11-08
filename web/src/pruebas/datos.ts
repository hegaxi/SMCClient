import type { ParametroInfo, ProcedimientoInfo } from '../tipos';

export const parametro = (p: Partial<ParametroInfo> & { nombre: string; tipo: string }): ParametroInfo => ({
  longitud: null, precision: null, escala: null, opcional: true, salida: false, descripcion: null, opciones: null, ...p,
});

export const procedimiento = (p: Partial<ProcedimientoInfo> & { nombre: string }): ProcedimientoInfo => ({
  descripcion: null, permiso: 'lectura', exentoSync: false, parametros: [], columnas: null, titulosResultados: null,
  titulo: p.nombre, accion: false, ...p,
});

/** fetch simulado: responde según método y ruta; guarda las peticiones. */
export function simularFetch(rutas: Record<string, (cuerpo: unknown) => { estado?: number; json: unknown }>) {
  const peticiones: { url: string; cuerpo: unknown }[] = [];
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const cuerpo = init?.body ? JSON.parse(String(init.body)) : undefined;
    peticiones.push({ url, cuerpo });
    const clave = `${init?.method ?? 'GET'} ${url}`;
    const r = rutas[clave];
    if (!r) return new Response(JSON.stringify({ title: `sin ruta ${clave}` }), { status: 404 });
    const { estado = 200, json } = r(cuerpo);
    return new Response(JSON.stringify(json), { status: estado, headers: { 'Content-Type': 'application/json' } });
  });
  vi.stubGlobal('fetch', fn);
  return peticiones;
}
