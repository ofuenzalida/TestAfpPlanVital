import type { Monthly, Portfolio, ProblemDetails, Summary } from './types';

/** Error de la API con un mensaje listo para mostrar. */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly problem?: ProblemDetails,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

const BASE_URL = import.meta.env.VITE_API_URL ?? '';

async function getJson<T>(path: string, params: Record<string, string>, signal?: AbortSignal): Promise<T> {
  const query = new URLSearchParams(params).toString();
  const url = `${BASE_URL}${path}${query ? `?${query}` : ''}`;

  let response: Response;
  try {
    response = await fetch(url, { signal, headers: { Accept: 'application/json' } });
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') throw e;
    throw new ApiError('No se pudo conectar con la API. Revisa que esté en ejecución.', 0);
  }

  if (!response.ok) {
    throw await toApiError(response);
  }
  return (await response.json()) as T;
}

/** Convierte una respuesta ProblemDetails en un mensaje legible. */
export async function toApiError(response: Response): Promise<ApiError> {
  let problem: ProblemDetails | undefined;
  try {
    problem = (await response.json()) as ProblemDetails;
  } catch {
    // cuerpo vacío o no JSON
  }

  const validation = problem?.errors ? Object.values(problem.errors).flat().join(' ') : '';
  const message =
    validation ||
    problem?.detail ||
    problem?.title ||
    `La API respondió con un error (${response.status}).`;

  return new ApiError(message, response.status, problem);
}

export const api = {
  getPortfolios: (signal?: AbortSignal) => getJson<Portfolio[]>('/api/portfolios', {}, signal),

  getSummary: (portfolioId: number, asOf: string, signal?: AbortSignal) =>
    getJson<Summary>(`/api/portfolios/${portfolioId}/performance/summary`, { asOf }, signal),

  getMonthly: (portfolioId: number, from: string, to: string, signal?: AbortSignal) =>
    getJson<Monthly>(`/api/portfolios/${portfolioId}/performance/monthly`, { from, to }, signal),
};
