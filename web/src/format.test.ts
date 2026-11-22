import { describe, expect, it } from 'vitest';
import { formatClp, formatDate, formatPercent } from './format';

// Se normalizan espacios por si la versión de ICU usa espacio no separable.
const norm = (s: string) => s.replace(/\s/g, ' ');

describe('formato es-CL', () => {
  it('porcentaje con coma decimal y signo', () => {
    expect(norm(formatPercent(0.024133))).toBe('+2,41%');
    expect(norm(formatPercent(-0.01))).toBe('-1,00%');
    expect(norm(formatPercent(0.0395))).toBe('+3,95%');
  });

  it('pesos chilenos con punto de miles y sin decimales', () => {
    expect(formatClp(1343330.9513)).toBe('$1.343.331');
    expect(formatClp(-23804.82)).toBe('$-23.805');
  });

  it('fecha dd-mm-aaaa', () => {
    expect(formatDate('2023-08-15')).toBe('15-08-2023');
  });

  it('sin dato', () => {
    expect(formatPercent(null)).toBe('—');
    expect(formatClp(undefined)).toBe('—');
  });
});
