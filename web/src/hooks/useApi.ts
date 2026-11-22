import { useEffect, useState } from 'react';

export type ApiState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'success'; data: T };

/**
 * Ejecuta una llamada a la API cada vez que cambian sus dependencias y expone
 * el estado (cargando, error, datos). Cancela la petición anterior si las
 * dependencias cambian antes de que responda, así no se pisan resultados.
 * Si `load` es null no se hace nada (estado idle).
 */
export function useApi<T>(
  load: ((signal: AbortSignal) => Promise<T>) | null,
  deps: unknown[],
): ApiState<T> {
  const [state, setState] = useState<ApiState<T>>({ status: 'idle' });

  useEffect(() => {
    if (!load) {
      setState({ status: 'idle' });
      return;
    }

    const controller = new AbortController();
    setState({ status: 'loading' });

    load(controller.signal)
      .then((data) => setState({ status: 'success', data }))
      .catch((e: unknown) => {
        if (controller.signal.aborted) return;
        const message = e instanceof Error ? e.message : 'Error inesperado.';
        setState({ status: 'error', message });
      });

    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return state;
}
