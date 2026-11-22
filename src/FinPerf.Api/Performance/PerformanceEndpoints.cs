using System.Globalization;
using FinPerf.Api.Contracts;
using FinPerf.Api.Data;
using Microsoft.AspNetCore.Http.HttpResults;

namespace FinPerf.Api.Performance;

public static class PerformanceEndpoints
{
    public const string DateFormat = "yyyy-MM-dd";

    public static IEndpointRouteBuilder MapPortfolioEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/portfolios").WithTags("Portfolios");

        group.MapGet("/", GetPortfolios);
        group.MapGet("/{id:int}/performance/summary", GetSummary);
        group.MapGet("/{id:int}/performance", GetRange);
        group.MapGet("/{id:int}/performance/monthly", GetMonthly);

        return app;
    }

    // GET /api/portfolios
    private static async Task<Ok<IEnumerable<PortfolioResponse>>> GetPortfolios(
        PortfolioCatalog catalog, CancellationToken ct)
    {
        var portfolios = await catalog.GetAllAsync(ct);
        return TypedResults.Ok(portfolios.Select(p => new PortfolioResponse(
            p.PortfolioId, p.Name, p.InceptionDate, p.FirstDataDate, p.LastDataDate)));
    }

    // GET /api/portfolios/{id}/performance/summary?asOf=yyyy-MM-dd
    private static async Task<Results<Ok<SummaryResponse>, ValidationProblem, ProblemHttpResult>> GetSummary(
        int id, string? asOf, PortfolioCatalog catalog, IPerformanceRepository repository, CancellationToken ct)
    {
        var errors = new Dictionary<string, string[]>();
        var asOfDate = ParseRequiredDate(asOf, "asOf", errors);
        if (errors.Count > 0) return TypedResults.ValidationProblem(errors);

        var portfolio = await catalog.FindAsync(id, ct);
        if (portfolio is null) return PortfolioNotFound(id);

        ValidateWithinData(portfolio, errors, ("asOf", asOfDate));
        if (errors.Count > 0) return TypedResults.ValidationProblem(errors);

        var rows = await repository.GetSummaryAsync(id, asOfDate, ct);
        return TypedResults.Ok(new SummaryResponse(
            id, asOfDate, rows.Select(PerformanceMapper.ToResponse).ToList()));
    }

    // GET /api/portfolios/{id}/performance?from=yyyy-MM-dd&to=yyyy-MM-dd
    private static async Task<Results<Ok<RangeResponse>, ValidationProblem, ProblemHttpResult>> GetRange(
        int id, string? from, string? to, PortfolioCatalog catalog, IPerformanceRepository repository, CancellationToken ct)
    {
        var (range, invalid, notFound) = await ValidateRangeAsync(id, from, to, catalog, ct);
        if (invalid is not null) return invalid;
        if (notFound is not null) return notFound;

        var row = await repository.GetRangeAsync(id, range.From, range.To, ct);
        return TypedResults.Ok(new RangeResponse(id, PerformanceMapper.ToResponse(row)));
    }

    // GET /api/portfolios/{id}/performance/monthly?from=yyyy-MM-dd&to=yyyy-MM-dd
    private static async Task<Results<Ok<MonthlyResponse>, ValidationProblem, ProblemHttpResult>> GetMonthly(
        int id, string? from, string? to, PortfolioCatalog catalog, IPerformanceRepository repository, CancellationToken ct)
    {
        var (range, invalid, notFound) = await ValidateRangeAsync(id, from, to, catalog, ct);
        if (invalid is not null) return invalid;
        if (notFound is not null) return notFound;

        var rows = await repository.GetMonthlyAsync(id, range.From, range.To, ct);
        return TypedResults.Ok(PerformanceMapper.ToResponse(id, range.From, range.To, rows));
    }

    // ---- Validación -------------------------------------------------------

    private static async Task<((DateOnly From, DateOnly To) Range, ValidationProblem? Invalid, ProblemHttpResult? NotFound)> ValidateRangeAsync(
        int id, string? from, string? to, PortfolioCatalog catalog, CancellationToken ct)
    {
        var errors = new Dictionary<string, string[]>();
        var fromDate = ParseRequiredDate(from, "from", errors);
        var toDate = ParseRequiredDate(to, "to", errors);
        if (errors.Count > 0) return (default, TypedResults.ValidationProblem(errors), null);

        if (fromDate > toDate)
        {
            errors["from"] = ["'from' debe ser menor o igual que 'to'."];
            return (default, TypedResults.ValidationProblem(errors), null);
        }

        var portfolio = await catalog.FindAsync(id, ct);
        if (portfolio is null) return (default, null, PortfolioNotFound(id));

        ValidateWithinData(portfolio, errors, ("from", fromDate), ("to", toDate));
        if (errors.Count > 0) return (default, TypedResults.ValidationProblem(errors), null);

        return ((fromDate, toDate), null, null);
    }

    private static DateOnly ParseRequiredDate(string? value, string name, Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors[name] = [$"'{name}' es obligatorio (formato {DateFormat})."];
            return default;
        }

        if (!DateOnly.TryParseExact(value, DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
        {
            errors[name] = [$"'{name}' no es una fecha válida; usa el formato {DateFormat}."];
            return default;
        }

        return date;
    }

    private static void ValidateWithinData(
        PortfolioRow portfolio, Dictionary<string, string[]> errors, params (string Name, DateOnly Value)[] dates)
    {
        if (portfolio.FirstDataDate is not { } first || portfolio.LastDataDate is not { } last)
        {
            errors["portfolio"] = [$"El portafolio {portfolio.PortfolioId} no tiene datos cargados."];
            return;
        }

        foreach (var (name, value) in dates)
        {
            if (value < first || value > last)
            {
                errors[name] = [
                    $"'{name}' debe estar dentro del rango con datos del portafolio: " +
                    $"{first.ToString(DateFormat, CultureInfo.InvariantCulture)} a " +
                    $"{last.ToString(DateFormat, CultureInfo.InvariantCulture)}."];
            }
        }
    }

    private static ProblemHttpResult PortfolioNotFound(int id) => TypedResults.Problem(
        statusCode: StatusCodes.Status404NotFound,
        title: "Portafolio no encontrado",
        detail: $"No existe el portafolio {id}.");
}
