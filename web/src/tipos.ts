// Contrato con ProcedimientosController (src/SMCClient.Api).

export interface OpcionParametro {
  valor: string;
  etiqueta: string;
}

export interface ParametroInfo {
  nombre: string;
  tipo: string;
  longitud: number | null;
  precision: number | null;
  escala: number | null;
  opcional: boolean;
  salida: boolean;
  descripcion: string | null;
  opciones: OpcionParametro[] | null;
  /** Lista que sale de otro procedimiento (smc:origen). */
  origen?: OrigenParametro | null;
  /** Separador si se pueden elegir varios valores (smc:multiple). */
  multiple?: string | null;
}

export interface OrigenParametro {
  procedimiento: string;
  valor: string;
  etiqueta: string | null;
  descripcion: string | null;
  /** Además de elegir, se puede escribir un valor nuevo. */
  libre: boolean;
}

export interface ColumnaInfo {
  nombre: string;
  tipo: string;
  nulo: boolean;
}

export interface ProcedimientoInfo {
  nombre: string;
  descripcion: string | null;
  permiso: string;
  exentoSync: boolean;
  parametros: ParametroInfo[];
  columnas: ColumnaInfo[] | null;
  titulosResultados: string[] | null;
  titulo: string;
  /** Modifica algo: no se ejecuta solo al abrirlo y pide confirmación. */
  accion: boolean;
  /** No aparece en el menú: lo usa una pantalla propia (p. ej. los campos de la búsqueda avanzada). */
  oculto: boolean;
  /** Ubicación en el menú (smc:menu): "Sección" o "Sección/Subgrupo". */
  menu?: string | null;
  /** Posición en el menú (smc:orden). */
  orden?: number | null;
  /** Procedimiento bajo el que aparece como sub-opción (smc:padre). */
  padre?: string | null;
}

export type Fila = Record<string, unknown>;

export interface ConjuntoResultados {
  columnas: ColumnaInfo[];
  filas: Fila[];
  truncado: boolean;
}

export interface ResultadoEjecucion {
  procedimiento: string;
  resultados: ConjuntoResultados[];
  salida: Record<string, unknown>;
}

export interface EstadoFuente {
  fuente: string;
  datosVigentes: boolean;
  sincronizando: boolean;
  ultimaSincronizacion: string | null;
}

export interface Problema {
  title?: string;
  status?: number;
  codigo?: string;
  errors?: Record<string, string[]>;
  fuentes?: EstadoFuente[];
}

/** Valores del formulario tal como los escribe el usuario (texto o casilla). */
export type ValoresFormulario = Record<string, string>;

export interface Sesion {
  usuario: string;
  nombre: string;
  roles: string | null;
  esAdministrador: boolean;
  /** Tiene la opción "Restablecer contraseña" (no es un procedimiento: la revisa la API). */
  puedeRestablecerContrasena?: boolean;
  debeCambiarContrasena: boolean;
}
