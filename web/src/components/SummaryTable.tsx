import type { PeriodPerformance } from '../api/types';
import { formatClp, formatDate, formatPercent } from '../format';

const LABELS: Record<PeriodPerformance['period'], string> = {
  MTD: 'Mes a la fecha',
  QTD: 'Trimestre a la fecha',
  YTD: 'Año a la fecha',
  ITD: 'Desde el inicio',
};

export function SummaryTable({ periods }: { periods: PeriodPerformance[] }) {
  return (
    <table className="summary">
      <thead>
        <tr>
          <th>Periodo</th>
          <th>Desde</th>
          <th className="num">Retorno</th>
          <th className="num">P&amp;L</th>
        </tr>
      </thead>
      <tbody>
        {periods.map((p) => (
          <tr key={p.period}>
            <th scope="row" title={LABELS[p.period]}>
              {p.period} <span className="muted">{LABELS[p.period]}</span>
            </th>
            <td>{formatDate(p.from)}</td>
            <td className={`num ${signClass(p.return)}`}>{formatPercent(p.return)}</td>
            <td className={`num ${signClass(p.pnL)}`}>{formatClp(p.pnL)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export const signClass = (v: number | null | undefined) =>
  v == null || v === 0 ? '' : v > 0 ? 'pos' : 'neg';
