import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ErrorApi } from './api';
import type { Fila } from './tipos';

export interface EstadoSincronizacion {
  /** null mientras se consulta por primera vez. */
  listo: boolean | null;
  fuentes: Fila[];
  entidades: Fila[];
  error: string | null;
  ultimaConsulta: Date | null;
}

const CADA_MS_PENDIENTE = 5_000;
const CADA_MS_LISTO = 60_000;

/**
 * Consulta api.Sync_Estado: cada 5 s mientras los datos no estén vigentes y cada minuto después
 * (para detectar si dejan de estarlo). Cualquier 503 de otro procedimiento llama a marcarPendiente().
 */
export function useSincronizacion(intervaloPendiente = CADA_MS_PENDIENTE, intervaloListo = CADA_MS_LISTO) {
  const [estado, setEstado] = useState<EstadoSincronizacion>({ listo: null, fuentes: [], entidades: [], error: null, ultimaConsulta: null });
  const temporizador = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const consultar = useCallback(async () => {
    clearTimeout(temporizador.current);
    let listo: boolean | null = null;
    try {
      const r = await api.ejecutar('Sync_Estado');
      const fuentes = r.resultados[0]?.filas ?? [];
      listo = fuentes.every((f) => f.DatosVigentes === true);
      setEstado({ listo, fuentes, entidades: r.resultados[1]?.filas ?? [], error: null, ultimaConsulta: new Date() });
    } catch (e) {
      const mensaje = e instanceof ErrorApi ? e.message : 'No se pudo consultar el estado de la sincronización.';
      setEstado((s) => ({ ...s, error: mensaje, ultimaConsulta: new Date() }));
    }
    temporizador.current = setTimeout(consultar, listo ? intervaloListo : intervaloPendiente);
  }, [intervaloPendiente, intervaloListo]);

  useEffect(() => {
    void consultar();
    return () => clearTimeout(temporizador.current);
  }, [consultar]);

  const marcarPendiente = useCallback(() => {
    setEstado((s) => ({ ...s, listo: false }));
    void consultar();
  }, [consultar]);

  const solicitar = useCallback(async () => {
    await api.ejecutar('Sync_Solicitar');
    void consultar();
  }, [consultar]);

  return { ...estado, refrescar: consultar, marcarPendiente, solicitar };
}
