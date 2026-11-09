import type { ProcedimientoInfo, Problema, ResultadoEjecucion, Sesion } from './tipos';

/** Error de la API con su ProblemDetails (title, codigo, errors por parámetro...). */
export class ErrorApi extends Error {
  constructor(public readonly estado: number, public readonly problema: Problema) {
    super(problema.title ?? `La API respondió ${estado}.`);
  }

  /** 503 sync.pendiente: los datos de Jira aún no están sincronizados. */
  get sincronizacionPendiente(): boolean {
    return this.estado === 503;
  }

  get codigo(): string | undefined {
    return this.problema.codigo;
  }
}

type Aviso = (e: ErrorApi) => void;
let alPerderSesion: Aviso = () => {};
let alDebeCambiar: Aviso = () => {};

/** La aplicación se entera cuando la sesión termina (401) o el usuario debe cambiar su contraseña. */
export function escucharSesion(perdida: Aviso, debeCambiar: Aviso) {
  alPerderSesion = perdida;
  alDebeCambiar = debeCambiar;
}

async function pedir<T>(url: string, init?: RequestInit, avisar = true): Promise<T> {
  let respuesta: Response;
  try {
    respuesta = await fetch(url, {
      credentials: 'same-origin',
      ...init,
      headers: {
        Accept: 'application/json',
        'X-SMC-Solicitud': '1', // protección CSRF: la API rechaza peticiones que modifican sin este encabezado
        ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
      },
    });
  } catch {
    throw new ErrorApi(0, { title: 'No hay conexión con el servidor.' });
  }
  if (!respuesta.ok) {
    let problema: Problema = {};
    try {
      problema = (await respuesta.json()) as Problema;
    } catch {
      // respuesta sin cuerpo JSON
    }
    if (respuesta.status === 429) problema.title ??= 'Demasiados intentos. Espere un minuto.';
    const error = new ErrorApi(respuesta.status, { status: respuesta.status, ...problema });
    if (avisar && respuesta.status === 401) alPerderSesion(error);
    if (avisar && error.codigo === 'contrasena.debe_cambiar') alDebeCambiar(error);
    throw error;
  }
  return respuesta.status === 204 ? (undefined as T) : ((await respuesta.json()) as T);
}

const post = (body: unknown) => ({ method: 'POST', body: JSON.stringify(body) });

export const api = {
  listar: () => pedir<ProcedimientoInfo[]>('/api/procedimientos'),
  ejecutar: (nombre: string, parametros: Record<string, unknown> = {}) =>
    pedir<ResultadoEjecucion>(`/api/procedimientos/${encodeURIComponent(nombre)}`, post(parametros)),
};

export const sesion = {
  obtener: () => pedir<Sesion>('/api/sesion', undefined, false),
  iniciar: (usuario: string, contrasena: string) => pedir<Sesion>('/api/sesion/iniciar', post({ usuario, contrasena }), false),
  cerrar: () => pedir<void>('/api/sesion/cerrar', { method: 'POST' }, false),
  cambiarContrasena: (actual: string, nueva: string) => pedir<void>('/api/sesion/cambiar-contrasena', post({ actual, nueva })),
  restablecerContrasena: (usuario: string, contrasenaTemporal: string) =>
    pedir<void>('/api/sesion/restablecer-contrasena', post({ usuario, contrasenaTemporal })),
};
