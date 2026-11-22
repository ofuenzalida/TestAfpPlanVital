using System.Net;
using System.Net.Http.Json;
using FinPerf.Api.Contracts;
using FinPerf.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FinPerf.Api.Tests;

/// <summary>
/// Tests de integración sobre el pipeline HTTP completo (routing, binding,
/// validación, ProblemDetails, serialización). Se reemplaza solo el repositorio
/// para no depender de SQL Server.
/// </summary>
public class PerformanceApiTests(PerformanceApiTests.ApiFactory factory) : IClassFixture<PerformanceApiTests.ApiFactory>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task Portfolios_Devuelve200ConLaLista()
    {
        var response = await _client.GetAsync("/api/portfolios");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<List<PortfolioResponse>>();
        var p = Assert.Single(body!);
        Assert.Equal(7, p.Id);
        Assert.Equal("Portafolio 7", p.Name);
    }

    [Fact]
    public async Task Rango_Valido_Devuelve200ConRetornoCompuesto()
    {
        var response = await _client.GetAsync("/api/portfolios/7/performance?from=2023-01-01&to=2023-08-15");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<RangeResponse>();
        Assert.Equal(7, body!.PortfolioId);
        Assert.Equal(0.0395, body.Performance.Return!.Value, 12); // EXP(LOG(1,0395)) - 1
        Assert.Equal(1_234.5m, body.Performance.PnL);
    }

    [Fact]
    public async Task Rango_FromMayorQueTo_Devuelve400ConProblemDetails()
    {
        var response = await _client.GetAsync("/api/portfolios/7/performance?from=2023-08-15&to=2023-01-01");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var problem = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        Assert.Equal(400, problem!.Status);
        Assert.True(problem.Errors.ContainsKey("from"));
    }

    [Theory]
    [InlineData("/api/portfolios/7/performance?to=2023-01-01", "from")]
    [InlineData("/api/portfolios/7/performance?from=15-08-2023&to=2023-09-01", "from")]
    [InlineData("/api/portfolios/7/performance?from=2023-01-01&to=2030-01-01", "to")]
    [InlineData("/api/portfolios/7/performance/monthly?from=2010-01-01&to=2023-01-01", "from")]
    [InlineData("/api/portfolios/7/performance/summary", "asOf")]
    [InlineData("/api/portfolios/7/performance/summary?asOf=2030-01-01", "asOf")]
    public async Task ParametrosInvalidos_Devuelven400(string url, string field)
    {
        var response = await _client.GetAsync(url);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<ValidationProblemDetails>();
        Assert.True(problem!.Errors.ContainsKey(field), $"Se esperaba un error en '{field}'.");
    }

    [Theory]
    [InlineData("/api/portfolios/999/performance?from=2023-01-01&to=2023-08-15")]
    [InlineData("/api/portfolios/999/performance/summary?asOf=2023-08-15")]
    [InlineData("/api/portfolios/999/performance/monthly?from=2023-01-01&to=2023-08-15")]
    public async Task PortafolioInexistente_Devuelve404ConProblemDetails(string url)
    {
        var response = await _client.GetAsync(url);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
        Assert.Equal(404, problem!.Status);
    }

    [Fact]
    public async Task Resumen_Devuelve200ConLosCuatroPeriodos()
    {
        var response = await _client.GetAsync("/api/portfolios/7/performance/summary?asOf=2023-08-15");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SummaryResponse>();
        Assert.Equal(["MTD", "QTD", "YTD", "ITD"], body!.Periods.Select(p => p.Period));
        Assert.Equal(-0.01, body.Periods[0].Return!.Value, 12);
        Assert.Null(body.Periods[1].Return); // periodo sin días con datos
        Assert.Equal(-1.0, body.Periods[2].Return!.Value); // [-100 %, +10 %] = -100 %
    }

    [Fact]
    public async Task Mensual_ComponeLosMesesEnElTotalAnual()
    {
        var response = await _client.GetAsync("/api/portfolios/7/performance/monthly?from=2023-01-01&to=2023-03-31");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<MonthlyResponse>();
        Assert.Equal(3, body!.Months.Count);
        Assert.Equal(0.10, body.Months[0].Return, 12);
        var year = Assert.Single(body.Years);
        Assert.Equal(0.0395, year.Return, 12);   // 1,10 × 0,90 × 1,05 − 1
        Assert.Equal(60m, year.PnL);
    }

    public sealed class ApiFactory : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IPerformanceRepository>();
                services.AddSingleton<IPerformanceRepository, FakeRepository>();
            });
        }
    }

    private sealed class FakeRepository : IPerformanceRepository
    {
        private static readonly DateOnly First = new(2015, 1, 1);
        private static readonly DateOnly Last = new(2024, 12, 31);

        public Task<IReadOnlyList<PortfolioRow>> GetPortfoliosAsync(CancellationToken ct) =>
            Task.FromResult<IReadOnlyList<PortfolioRow>>(
                [new PortfolioRow(7, "Portafolio 7", First, First, Last)]);

        public Task<IReadOnlyList<PeriodRow>> GetSummaryAsync(int portfolioId, DateOnly asOf, CancellationToken ct) =>
            Task.FromResult<IReadOnlyList<PeriodRow>>(
            [
                new("MTD", asOf, asOf, asOf, asOf, 2, 0, Math.Log(1.10) + Math.Log(0.90), 10m),
                new("QTD", asOf, asOf, null, null, 0, 0, null, null),
                new("YTD", asOf, asOf, asOf, asOf, 2, 1, Math.Log(1.10), -95m),
                new("ITD", First, asOf, First, asOf, 1, 0, Math.Log(1.05), 5m),
            ]);

        public Task<RangeRow> GetRangeAsync(int portfolioId, DateOnly from, DateOnly to, CancellationToken ct) =>
            Task.FromResult(new RangeRow(from, to, from, to, 3, 0, Math.Log(1.0395), 1_234.5m));

        public Task<IReadOnlyList<MonthRow>> GetMonthlyAsync(int portfolioId, DateOnly from, DateOnly to, CancellationToken ct) =>
            Task.FromResult<IReadOnlyList<MonthRow>>(
            [
                new(2023, 1, new(2023, 1, 2), new(2023, 1, 31), 22, 0, Math.Log(1.10), 10m),
                new(2023, 2, new(2023, 2, 1), new(2023, 2, 28), 20, 0, Math.Log(0.90), 20m),
                new(2023, 3, new(2023, 3, 1), new(2023, 3, 31), 23, 0, Math.Log(1.05), 30m),
            ]);
    }
}
