import type { Monthly } from '../api/types';
import { MONTHS, formatClp, formatPercent } from '../format';
import { signClass } from './SummaryTable';
import { buildYearRows } from '../monthlyGrid';

/** Retornos mensuales: años en filas, meses en columnas y total anual compuesto. */
export function MonthlyTable({ monthly }: { monthly: Monthly }) {
  const rows = buildYearRows(monthly);

  return (
    <div className="table-scroll">
      <table className="monthly">
        <thead>
          <tr>
            <th>Año</th>
            {MONTHS.map((m) => <th key={m} className="num">{m}</th>)}
            <th className="num">Año</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.year}>
              <th scope="row">{row.year}</th>
              {row.months.map((m, i) => (
                <td
                  key={i}
                  className={`num ${signClass(m?.return)}`}
                  title={m ? `P&L: ${formatClp(m.pnL)} · ${m.daysWithData} días` : 'Sin datos'}
                >
                  {formatPercent(m?.return)}
                </td>
              ))}
              <td
                className={`num total ${signClass(row.total?.return)}`}
                title={row.total ? `P&L: ${formatClp(row.total.pnL)}` : undefined}
              >
                {formatPercent(row.total?.return)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
