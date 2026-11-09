import type { AccionListado, Fila, ProcedimientoInfo, ValoresFormulario } from './tipos';

/** Valor de una celda como texto de formulario (Sí/No -> 'true'/'false', vacío -> ''). */
export function textoDeValor(v: unknown): string {
  if (v === null || v === undefined) return '';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return String(v);
}

/** "¿Eliminar el rol {Nombre}?" con los valores de la fila (o del formulario). */
export function reemplazar(plantilla: string, datos: Record<string, unknown>): string {
  return plantilla.replace(/\{(\w+)\}/g, (_, c: string) => {
    const v = datos[c];
    return typeof v === 'boolean' ? (v ? 'Sí' : 'No') : textoDeValor(v);
  });
}

/** Valores iniciales del formulario de una acción: "{Columna}" toma el de la fila; lo demás es fijo. */
export function valoresDeAccion(accion: AccionListado, fila?: Fila): ValoresFormulario {
  const r: ValoresFormulario = {};
  for (const [param, plantilla] of Object.entries(accion.valores ?? {})) {
    const m = /^\{(\w+)\}$/.exec(plantilla);
    r[param] = m ? textoDeValor(fila?.[m[1]]) : reemplazar(plantilla, fila ?? {});
  }
  return r;
}

/** La acción se ofrece si el usuario puede ejecutar su procedimiento o abrir su pantalla. */
export function accionDisponible(accion: AccionListado, catalogo: ProcedimientoInfo[], vistasPropias: string[] = []): boolean {
  if (accion.proc) return catalogo.some((p) => p.nombre === accion.proc);
  if (accion.vista) return vistasPropias.includes(accion.vista) || catalogo.some((p) => p.nombre === accion.vista);
  return false;
}

/** ocultarSi: {"EsSistema": true} no se muestra en los roles del sistema. */
export function accionVisibleEnFila(accion: AccionListado, fila: Fila): boolean {
  return !Object.entries(accion.ocultarSi ?? {}).some(([c, v]) => fila[c] === v);
}
