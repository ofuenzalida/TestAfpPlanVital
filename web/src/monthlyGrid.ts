import type { MonthPerformance, Monthly, YearPerformance } from './api/types';

export interface YearRow {
  year: number;
  /** 12 posiciones (enero a diciembre); null si el mes no tiene datos en el rango. */
  months: (MonthPerformance | null)[];
  total: YearPerformance | null;
}

/** Pasa la lista plana de meses a una grilla año × mes, años más recientes primero. */
export function buildYearRows(monthly: Monthly): YearRow[] {
  const byYear = new Map<number, YearRow>();

  for (const m of monthly.months) {
    let row = byYear.get(m.year);
    if (!row) {
      row = { year: m.year, months: Array(12).fill(null), total: null };
      byYear.set(m.year, row);
    }
    row.months[m.month - 1] = m;
  }

  for (const y of monthly.years) {
    const row = byYear.get(y.year);
    if (row) row.total = y;
  }

  return [...byYear.values()].sort((a, b) => b.year - a.year);
}
