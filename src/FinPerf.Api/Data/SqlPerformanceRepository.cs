using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace FinPerf.Api.Data;

public sealed class DatabaseOptions
{
    public const string ConnectionStringName = "FinPerf";

    public string ConnectionString { get; set; } = string.Empty;
}

/// <summary>
/// Implementación con Dapper. Se eligió Dapper y no EF Core porque las consultas
/// son pocas, de solo lectura y ya están afinadas a mano en SQL (funciones inline
/// sobre la tabla pre-agregada): no hace falta tracking, migraciones de EF ni
/// traducción de LINQ, y Dapper deja ver exactamente qué SQL se ejecuta.
/// </summary>
public sealed class SqlPerformanceRepository(IOptions<DatabaseOptions> options) : IPerformanceRepository
{
    private readonly string _connectionString = options.Value.ConnectionString;

    public async Task<IReadOnlyList<PortfolioRow>> GetPortfoliosAsync(CancellationToken ct)
    {
        const string sql = """
            SELECT PortfolioId, Name, InceptionDate, FirstDataDate, LastDataDate
            FROM dbo.vw_PortfolioInfo
            ORDER BY PortfolioId;
            """;

        await using var cn = await OpenAsync(ct);
        var rows = await cn.QueryAsync<PortfolioRecord>(new CommandDefinition(sql, cancellationToken: ct));
        return rows.Select(r => new PortfolioRow(
                r.PortfolioId, r.Name, ToDate(r.InceptionDate),
                ToDate(r.FirstDataDate), ToDate(r.LastDataDate)))
            .ToList();
    }

    public async Task<IReadOnlyList<PeriodRow>> GetSummaryAsync(int portfolioId, DateOnly asOf, CancellationToken ct)
    {
        const string sql = """
            SELECT Period, FromDate, ToDate, FirstDataDate, LastDataDate,
                   DaysWithData, SumLogReturn, PnL
            FROM dbo.tvf_PerformanceSummary(@PortfolioId, @AsOf)
            ORDER BY SortOrder;
            """;

        var p = new DynamicParameters();
        p.Add("PortfolioId", portfolioId, DbType.Int32);
        p.Add("AsOf", ToDateTime(asOf), DbType.Date);

        await using var cn = await OpenAsync(ct);
        var rows = await cn.QueryAsync<PeriodRecord>(new CommandDefinition(sql, p, cancellationToken: ct));
        return rows.Select(r => new PeriodRow(
                r.Period, ToDate(r.FromDate), ToDate(r.ToDate),
                ToDate(r.FirstDataDate), ToDate(r.LastDataDate),
                r.DaysWithData, r.SumLogReturn, r.PnL))
            .ToList();
    }

    public async Task<RangeRow> GetRangeAsync(int portfolioId, DateOnly from, DateOnly to, CancellationToken ct)
    {
        const string sql = """
            SELECT FromDate, ToDate, FirstDataDate, LastDataDate,
                   DaysWithData, SumLogReturn, PnL
            FROM dbo.tvf_PerformanceRange(@PortfolioId, @From, @To);
            """;

        await using var cn = await OpenAsync(ct);
        var r = await cn.QuerySingleAsync<RangeRecord>(
            new CommandDefinition(sql, RangeParameters(portfolioId, from, to), cancellationToken: ct));
        return new RangeRow(
            ToDate(r.FromDate), ToDate(r.ToDate),
            ToDate(r.FirstDataDate), ToDate(r.LastDataDate),
            r.DaysWithData, r.SumLogReturn, r.PnL);
    }

    public async Task<IReadOnlyList<MonthRow>> GetMonthlyAsync(int portfolioId, DateOnly from, DateOnly to, CancellationToken ct)
    {
        const string sql = """
            SELECT [Year], [Month], FirstDataDate, LastDataDate,
                   DaysWithData, SumLogReturn, PnL
            FROM dbo.tvf_PerformanceMonthly(@PortfolioId, @From, @To)
            ORDER BY [Year], [Month];
            """;

        await using var cn = await OpenAsync(ct);
        var rows = await cn.QueryAsync<MonthRecord>(
            new CommandDefinition(sql, RangeParameters(portfolioId, from, to), cancellationToken: ct));
        return rows.Select(r => new MonthRow(
                r.Year, r.Month, ToDate(r.FirstDataDate), ToDate(r.LastDataDate),
                r.DaysWithData, r.SumLogReturn, r.PnL))
            .ToList();
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_connectionString))
        {
            throw new InvalidOperationException(
                $"Falta la cadena de conexión 'ConnectionStrings:{DatabaseOptions.ConnectionStringName}'. " +
                "Configúrala con la variable de entorno ConnectionStrings__FinPerf o con dotnet user-secrets.");
        }

        var cn = new SqlConnection(_connectionString);
        await cn.OpenAsync(ct);
        return cn;
    }

    private static DynamicParameters RangeParameters(int portfolioId, DateOnly from, DateOnly to)
    {
        var p = new DynamicParameters();
        p.Add("PortfolioId", portfolioId, DbType.Int32);
        p.Add("From", ToDateTime(from), DbType.Date);
        p.Add("To", ToDateTime(to), DbType.Date);
        return p;
    }

    private static DateTime ToDateTime(DateOnly d) => d.ToDateTime(TimeOnly.MinValue);
    private static DateOnly ToDate(DateTime d) => DateOnly.FromDateTime(d);
    private static DateOnly? ToDate(DateTime? d) => d is null ? null : DateOnly.FromDateTime(d.Value);

    // Clases de materialización (propiedades con set: el mapeo de Dapper más
    // tolerante a diferencias de tipo). SQL Server devuelve DATE como DateTime.
    private sealed class PortfolioRecord
    {
        public int PortfolioId { get; set; }
        public string Name { get; set; } = "";
        public DateTime InceptionDate { get; set; }
        public DateTime? FirstDataDate { get; set; }
        public DateTime? LastDataDate { get; set; }
    }

    private class RangeRecord
    {
        public DateTime FromDate { get; set; }
        public DateTime ToDate { get; set; }
        public DateTime? FirstDataDate { get; set; }
        public DateTime? LastDataDate { get; set; }
        public int DaysWithData { get; set; }
        public double? SumLogReturn { get; set; }
        public decimal? PnL { get; set; }
    }

    private sealed class PeriodRecord : RangeRecord
    {
        public string Period { get; set; } = "";
    }

    private sealed class MonthRecord
    {
        public int Year { get; set; }
        public int Month { get; set; }
        public DateTime FirstDataDate { get; set; }
        public DateTime LastDataDate { get; set; }
        public int DaysWithData { get; set; }
        public double SumLogReturn { get; set; }
        public decimal PnL { get; set; }
    }
}
