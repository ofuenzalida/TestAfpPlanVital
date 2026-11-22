using FinPerf.Api.Contracts;
using FinPerf.Api.Data;
using FinPerf.Domain;

namespace FinPerf.Api.Performance;

/// <summary>
/// Convierte las filas de SQL (Σ LOG(1 + r) y P&amp;L) en respuestas de la API.
/// Toda conversión a retorno pasa por <see cref="Compounding"/>.
/// </summary>
public static class PerformanceMapper
{
    public static PerformanceResponse ToResponse(RangeRow r) => new(
        r.FromDate, r.ToDate, r.FirstDataDate, r.LastDataDate, r.DaysWithData,
        ReturnOf(r.DaysWithData, r.TotalLossDays, r.SumLogReturn), PnLOf(r.DaysWithData, r.PnL));

    public static PeriodPerformanceResponse ToResponse(PeriodRow r) => new(
        r.Period, r.FromDate, r.ToDate, r.FirstDataDate, r.LastDataDate, r.DaysWithData,
        ReturnOf(r.DaysWithData, r.TotalLossDays, r.SumLogReturn), PnLOf(r.DaysWithData, r.PnL));

    public static MonthlyResponse ToResponse(int portfolioId, DateOnly from, DateOnly to, IReadOnlyList<MonthRow> rows)
    {
        var months = rows
            .Select(m => new MonthPerformanceResponse(
                m.Year, m.Month, m.FirstDataDate, m.LastDataDate, m.DaysWithData,
                Compounding.FromLogGrowth(m.SumLogReturn, m.TotalLossDays), m.PnL))
            .ToList();

        // Retorno anual = composición de los retornos mensuales (idea 4).
        var years = months
            .GroupBy(m => m.Year)
            .Select(g => new YearPerformanceResponse(
                g.Key,
                g.Count(),
                Compounding.Compound(g.Select(m => m.Return)),
                g.Sum(m => m.PnL)))
            .ToList();

        return new MonthlyResponse(portfolioId, from, to, months, years);
    }

    private static double? ReturnOf(int days, int totalLossDays, double? sumLog) =>
        days == 0 || sumLog is null ? null : Compounding.FromLogGrowth(sumLog.Value, totalLossDays);

    private static decimal? PnLOf(int days, decimal? pnl) => days == 0 ? null : pnl;
}
