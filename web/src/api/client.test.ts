import { describe, expect, it } from 'vitest';
import { toApiError } from './client';
import { buildYearRows } from '../monthlyGrid';

const problem = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/problem+json' } });

describe('toApiError', () => {
  it('usa los mensajes de validación de un 400', async () => {
    const err = await toApiError(problem(400, {
      title: 'One or more validation errors occurred.',
      status: 400,
      errors: { from: ["'from' debe ser menor o igual que 'to'."] },
    }));
    expect(err.status).toBe(400);
    expect(err.message).toBe("'from' debe ser menor o igual que 'to'.");
  });

  it('usa el detail de un 404', async () => {
    const err = await toApiError(problem(404, { title: 'Portafolio no encontrado', detail: 'No existe el portafolio 99.' }));
    expect(err.message).toBe('No existe el portafolio 99.');
  });

  it('tiene un mensaje genérico si el cuerpo no es JSON', async () => {
    const err = await toApiError(new Response('boom', { status: 500 }));
    expect(err.message).toContain('500');
  });
});

describe('buildYearRows', () => {
  it('arma años en filas y meses en columnas, años recientes primero', () => {
    const rows = buildYearRows({
      portfolioId: 7, from: '2022-12-01', to: '2023-02-28',
      months: [
        { year: 2022, month: 12, firstDataDate: '', lastDataDate: '', daysWithData: 22, return: 0.01, pnL: 1 },
        { year: 2023, month: 2, firstDataDate: '', lastDataDate: '', daysWithData: 20, return: 0.02, pnL: 2 },
      ],
      years: [
        { year: 2022, monthsWithData: 1, return: 0.01, pnL: 1 },
        { year: 2023, monthsWithData: 1, return: 0.02, pnL: 2 },
      ],
    });
    expect(rows.map((r) => r.year)).toEqual([2023, 2022]);
    expect(rows[0].months[0]).toBeNull();
    expect(rows[0].months[1]?.return).toBe(0.02);
    expect(rows[1].months[11]?.return).toBe(0.01);
    expect(rows[0].total?.return).toBe(0.02);
  });
});
