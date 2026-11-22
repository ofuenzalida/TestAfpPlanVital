import type { Portfolio } from '../api/types';
import { formatDate } from '../format';

interface Props {
  portfolios: Portfolio[];
  portfolioId: number | null;
  asOf: string;
  onPortfolioChange: (id: number) => void;
  onAsOfChange: (date: string) => void;
}

export function Filters({ portfolios, portfolioId, asOf, onPortfolioChange, onAsOfChange }: Props) {
  const selected = portfolios.find((p) => p.id === portfolioId);

  return (
    <form className="filters" onSubmit={(e) => e.preventDefault()}>
      <label>
        Portafolio
        <select
          value={portfolioId ?? ''}
          onChange={(e) => onPortfolioChange(Number(e.target.value))}
        >
          {portfolios.map((p) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
      </label>

      <label>
        Fecha de corte
        <input
          type="date"
          value={asOf}
          min={selected?.firstDataDate ?? undefined}
          max={selected?.lastDataDate ?? undefined}
          onChange={(e) => onAsOfChange(e.target.value)}
          required
        />
      </label>

      {selected && (
        <small className="filters__hint">
          Datos disponibles: {formatDate(selected.firstDataDate)} a {formatDate(selected.lastDataDate)}
        </small>
      )}
    </form>
  );
}
