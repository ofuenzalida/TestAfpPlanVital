namespace FinPerf.Api.Contracts;

// Los retornos van como fracción (0,0241 = 2,41 %) y el P&L en la moneda base.
// Return y PnL son null cuando el periodo no tiene días con datos.

public sealed record PortfolioResponse(
    int Id,
    string Name,
    DateOnly InceptionDate,
    DateOnly? FirstDataDate,
    DateOnly? LastDataDate);

public sealed record PerformanceResponse(
    DateOnly From,
    DateOnly To,
    DateOnly? FirstDataDate,
    DateOnly? LastDataDate,
    int DaysWithData,
    double? Return,
    decimal? PnL);

public sealed record PeriodPerformanceResponse(
    string Period,
    DateOnly From,
    DateOnly To,
    DateOnly? FirstDataDate,
    DateOnly? LastDataDate,
    int DaysWithData,
    double? Return,
    decimal? PnL);

public sealed record SummaryResponse(
    int PortfolioId,
    DateOnly AsOf,
    IReadOnlyList<PeriodPerformanceResponse> Periods);

public sealed record RangeResponse(
    int PortfolioId,
    PerformanceResponse Performance);

public sealed record MonthPerformanceResponse(
    int Year,
    int Month,
    DateOnly FirstDataDate,
    DateOnly LastDataDate,
    int DaysWithData,
    double Return,
    decimal PnL);

/// <summary>Total de un año calculado componiendo sus meses (dentro del rango pedido).</summary>
public sealed record YearPerformanceResponse(
    int Year,
    int MonthsWithData,
    double Return,
    decimal PnL);

public sealed record MonthlyResponse(
    int PortfolioId,
    DateOnly From,
    DateOnly To,
    IReadOnlyList<MonthPerformanceResponse> Months,
    IReadOnlyList<YearPerformanceResponse> Years);
