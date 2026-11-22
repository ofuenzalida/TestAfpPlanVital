import { useEffect, useState } from 'react';
import { api } from './api/client';
import { Filters } from './components/Filters';
import { MonthlyTable } from './components/MonthlyTable';
import { StatusMessage } from './components/StatusMessage';
import { SummaryTable } from './components/SummaryTable';
import { formatDate } from './format';
import { useApi } from './hooks/useApi';

export default function App() {
  const portfolios = useApi((signal) => api.getPortfolios(signal), []);

  const [portfolioId, setPortfolioId] = useState<number | null>(null);
  const [asOf, setAsOf] = useState('');

  // Al cargar la lista, seleccionar el primer portafolio y su último día con datos.
  useEffect(() => {
    if (portfolios.status === 'success' && portfolioId === null && portfolios.data.length > 0) {
      const first = portfolios.data[0];
      setPortfolioId(first.id);
      setAsOf(first.lastDataDate ?? '');
    }
  }, [portfolios, portfolioId]);

  const selected = portfolios.status === 'success'
    ? portfolios.data.find((p) => p.id === portfolioId)
    : undefined;
  const ready = selected != null && asOf !== '';

  const summary = useApi(
    ready ? (signal) => api.getSummary(selected.id, asOf, signal) : null,
    [selected?.id, asOf],
  );

  // Tabla mensual: desde el primer día con datos hasta la fecha de corte.
  const monthly = useApi(
    ready && selected.firstDataDate
      ? (signal) => api.getMonthly(selected.id, selected.firstDataDate!, asOf, signal)
      : null,
    [selected?.id, selected?.firstDataDate, asOf],
  );

  return (
    <main className="page">
      <h1>Rendimiento de portafolios</h1>

      <StatusMessage
        state={portfolios}
        loadingText="Cargando portafolios…"
        isEmpty={(list) => list.length === 0}
        emptyText="No hay portafolios disponibles."
      >
        {(list) => (
          <Filters
            portfolios={list}
            portfolioId={portfolioId}
            asOf={asOf}
            onPortfolioChange={setPortfolioId}
            onAsOfChange={setAsOf}
          />
        )}
      </StatusMessage>

      {ready && (
        <>
          <section>
            <h2>Resumen al {formatDate(asOf)}</h2>
            <StatusMessage
              state={summary}
              loadingText="Calculando resumen…"
              isEmpty={(s) => s.periods.every((p) => p.daysWithData === 0)}
              emptyText="No hay datos hasta la fecha de corte seleccionada."
            >
              {(s) => <SummaryTable periods={s.periods} />}
            </StatusMessage>
          </section>

          <section>
            <h2>Retornos mensuales</h2>
            <StatusMessage
              state={monthly}
              loadingText="Cargando retornos mensuales…"
              isEmpty={(m) => m.months.length === 0}
              emptyText="No hay meses con datos en el rango."
            >
              {(m) => <MonthlyTable monthly={m} />}
            </StatusMessage>
          </section>
        </>
      )}
    </main>
  );
}
