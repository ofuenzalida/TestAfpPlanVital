namespace FinPerf.Api.Data;

/// <summary>
/// Acceso a datos de rendimiento. La implementación real usa Dapper contra las
/// funciones de db/migrations/004_consultas_api.sql; los tests la reemplazan.
/// </summary>
public interface IPerformanceRepository
{
    Task<IReadOnlyList<PortfolioRow>> GetPortfoliosAsync(CancellationToken ct);

    Task<IReadOnlyList<PeriodRow>> GetSummaryAsync(int portfolioId, DateOnly asOf, CancellationToken ct);

    Task<RangeRow> GetRangeAsync(int portfolioId, DateOnly from, DateOnly to, CancellationToken ct);

    Task<IReadOnlyList<MonthRow>> GetMonthlyAsync(int portfolioId, DateOnly from, DateOnly to, CancellationToken ct);
}

public sealed record PortfolioRow(
    int PortfolioId,
    string Name,
    DateOnly InceptionDate,
    DateOnly? FirstDataDate,
    DateOnly? LastDataDate);

/// <summary>Una fila por periodo (MTD, QTD, YTD, ITD).</summary>
public sealed record PeriodRow(
    string Period,
    DateOnly FromDate,
    DateOnly ToDate,
    DateOnly? FirstDataDate,
    DateOnly? LastDataDate,
    int DaysWithData,
    int TotalLossDays,
    double? SumLogReturn,
    decimal? PnL);

public sealed record RangeRow(
    DateOnly FromDate,
    DateOnly ToDate,
    DateOnly? FirstDataDate,
    DateOnly? LastDataDate,
    int DaysWithData,
    int TotalLossDays,
    double? SumLogReturn,
    decimal? PnL);

public sealed record MonthRow(
    int Year,
    int Month,
    DateOnly FirstDataDate,
    DateOnly LastDataDate,
    int DaysWithData,
    int TotalLossDays,
    double SumLogReturn,
    decimal PnL);
