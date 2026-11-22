import type { ApiState } from '../hooks/useApi';
import type { ReactNode } from 'react';

interface Props<T> {
  state: ApiState<T>;
  /** Devuelve true si los datos están vacíos (se muestra `emptyText`). */
  isEmpty?: (data: T) => boolean;
  emptyText?: string;
  loadingText?: string;
  children: (data: T) => ReactNode;
}

/** Muestra el mensaje de carga, error o sin datos; si hay datos, delega en children. */
export function StatusMessage<T>({
  state,
  isEmpty,
  emptyText = 'No hay datos para los filtros seleccionados.',
  loadingText = 'Cargando…',
  children,
}: Props<T>) {
  switch (state.status) {
    case 'idle':
      return null;
    case 'loading':
      return <p className="status status--loading" role="status">{loadingText}</p>;
    case 'error':
      return <p className="status status--error" role="alert">{state.message}</p>;
    case 'success':
      return isEmpty?.(state.data)
        ? <p className="status status--empty">{emptyText}</p>
        : <>{children(state.data)}</>;
  }
}
