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
  /** Valor por omisión que declara el procedimiento (null si es NULL). */
  porOmision?: string | null;
  /** smc:inicial: con qué se llena el campo al abrir (inicio_mes | hoy). */
  inicial?: string | null;
}

export interface OrigenParametro {
  procedimiento: string;
  valor: string;
  etiqueta: string | null;
  descripcion: string | null;
  /** Además de elegir, se puede escribir un valor nuevo. */
  libre: boolean;
  /** Parámetros del procedimiento de la lista; "@Campo" = el valor de ese campo del formulario (listas dependientes). */
  parametros?: Record<string, string> | null;
}

/** Botón de un listado (smc:acciones): "Nuevo …" arriba o una acción por fila (ver db/11_DatosSemilla/093_Acciones.sql). */
export interface AccionListado {
  etiqueta: string;
  /** Procedimiento que ejecuta (abre su formulario, o directo tras confirmar). */
  proc?: string;
  /** Pantalla a la que lleva (otro procedimiento o una vista propia como _restablecer). */
  vista?: string;
  /** true = en cada fila; false = arriba del listado. */
  fila: boolean;
  /** "{Columna}" = valor de la fila; otro texto, fijo. */
  valores?: Record<string, string>;
  /** Parámetros que no se pueden cambiar (la llave del registro). */
  bloquear?: string[];
  /** Sin formulario: confirma y ejecuta. */
  directo?: boolean;
  confirmar?: string;
  exito?: string;
  peligro?: boolean;
  /** No se muestra en las filas con estos valores. */
  ocultarSi?: Record<string, unknown>;
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
  /** Botones "Nuevo" y acciones por fila del listado (smc:acciones). */
  acciones?: AccionListado[] | null;
  /** Columnas que no se muestran hasta "Más columnas" (smc:columnasSecundarias). */
  columnasSecundarias?: string[] | null;
  /** Qué significa cada columna (smc:ayudaColumnas): se muestra al pasar sobre el encabezado. */
  ayudaColumnas?: Record<string, string> | null;
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
