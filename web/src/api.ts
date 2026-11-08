import type { ProcedimientoInfo, Problema, ResultadoEjecucion } from './tipos';

/** Error de la API con su ProblemDetails (title, codigo, errors por parámetro...). */
export class ErrorApi extends Error {
  constructor(public readonly estado: number, public readonly problema: Problema) {
    super(problema.title ?? `La API respondió ${estado}.`);
  }

  /** 503 sync.pendiente: los datos de Jira aún no están sincronizados. */
  get sincronizacionPendiente(): boolean {
    return this.estado === 503;
  }
}

async function pedir<T>(url: string, init?: RequestInit): Promise<T> {
  let respuesta: Response;
  try {
    respuesta = await fetch(url, {
      credentials: 'same-origin', // autenticación de Windows del navegador
      ...init,
      headers: { Accept: 'application/json', ...(init?.body ? { 'Content-Type': 'application/json' } : {}) },
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
    if (respuesta.status === 401) problema.title ??= 'Su sesión no está autenticada en el dominio.';
    throw new ErrorApi(respuesta.status, { status: respuesta.status, ...problema });
  }
  return (await respuesta.json()) as T;
}

export const api = {
  listar: () => pedir<ProcedimientoInfo[]>('/api/procedimientos'),
  ejecutar: (nombre: string, parametros: Record<string, unknown> = {}) =>
    pedir<ResultadoEjecucion>(`/api/procedimientos/${encodeURIComponent(nombre)}`, {
      method: 'POST',
      body: JSON.stringify(parametros),
    }),
};
