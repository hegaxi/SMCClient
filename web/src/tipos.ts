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
