// Formato chileno (es-CL): coma decimal, punto de miles, peso sin decimales.

const percent = new Intl.NumberFormat('es-CL', {
  style: 'percent',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
  signDisplay: 'exceptZero',
});

const clp = new Intl.NumberFormat('es-CL', {
  style: 'currency',
  currency: 'CLP',
  maximumFractionDigits: 0,
});

const date = new Intl.DateTimeFormat('es-CL', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'UTC' });

const SIN_DATO = '—';

/** 0.024133 -> "+2,41%" */
export const formatPercent = (value: number | null | undefined): string =>
  value == null ? SIN_DATO : percent.format(value);

/** 1343330.95 -> "$1.343.331" */
export const formatClp = (value: number | null | undefined): string =>
  value == null ? SIN_DATO : clp.format(value);

/** "2023-08-15" -> "15-08-2023" */
export const formatDate = (isoDate: string | null | undefined): string =>
  isoDate ? date.format(new Date(`${isoDate}T00:00:00Z`)).replaceAll('/', '-') : SIN_DATO;

export const MONTHS = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
