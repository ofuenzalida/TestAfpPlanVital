// Contratos de la API (.NET). Fechas en formato yyyy-MM-dd.
// Los retornos vienen como fracción (0.0241 = 2,41 %); null = sin días con datos.

export interface Portfolio {
  id: number;
  name: string;
  inceptionDate: string;
  firstDataDate: string | null;
  lastDataDate: string | null;
}

export interface PeriodPerformance {
  period: 'MTD' | 'QTD' | 'YTD' | 'ITD';
  from: string;
  to: string;
  firstDataDate: string | null;
  lastDataDate: string | null;
  daysWithData: number;
  return: number | null;
  pnL: number | null;
}

export interface Summary {
  portfolioId: number;
  asOf: string;
  periods: PeriodPerformance[];
}

export interface MonthPerformance {
  year: number;
  month: number;
  firstDataDate: string;
  lastDataDate: string;
  daysWithData: number;
  return: number;
  pnL: number;
}

export interface YearPerformance {
  year: number;
  monthsWithData: number;
  return: number;
  pnL: number;
}

export interface Monthly {
  portfolioId: number;
  from: string;
  to: string;
  months: MonthPerformance[];
  years: YearPerformance[];
}

/** RFC 7807 (ProblemDetails / ValidationProblemDetails de ASP.NET Core). */
export interface ProblemDetails {
  title?: string;
  detail?: string;
  status?: number;
  errors?: Record<string, string[]>;
}
