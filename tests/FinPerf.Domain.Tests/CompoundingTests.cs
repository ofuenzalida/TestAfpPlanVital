using FinPerf.Domain;

namespace FinPerf.Domain.Tests;

public class CompoundingTests
{
    private const int Precision = 12;

    // Casos de control del enunciado.

    [Fact]
    public void Compound_MasDiezMenosDiez_DaMenosUnoPorCiento()
    {
        var result = Compounding.Compound(new[] { 0.10, -0.10 });

        Assert.Equal(-0.01, result, Precision);
    }

    [Fact]
    public void Compound_TresDias_DaTresComaNoventaYCincoPorCiento()
    {
        var result = Compounding.Compound(new[] { 0.10, -0.10, 0.05 });

        Assert.Equal(0.0395, result, Precision);
    }

    [Fact]
    public void PortfolioReturn_InstrumentosAyB_DaCeroComaCuatroCincoPorCiento()
    {
        var positions = new[]
        {
            new PositionDay(MarketValueBegin: 1_000_000m, PnL: 10_000m), // A: +1 %
            new PositionDay(MarketValueBegin: 100_000m, PnL: -5_000m),   // B: -5 %
        };

        var result = Compounding.PortfolioReturn(positions);

        Assert.NotNull(result);
        Assert.Equal(0.004545, result!.Value, 6);          // +0,4545 %
        Assert.Equal(5_000.0 / 1_100_000.0, result.Value, Precision);
    }

    [Fact]
    public void PortfolioReturn_NoEsElPromedioSimple()
    {
        var positions = new[]
        {
            new PositionDay(1_000_000m, 10_000m),
            new PositionDay(100_000m, -5_000m),
        };
        var simpleAverage = (0.01 + -0.05) / 2; // -2 %

        var result = Compounding.PortfolioReturn(positions);

        Assert.NotEqual(simpleAverage, result!.Value, 6);
        Assert.True(result > 0);
    }

    // La forma logarítmica (la que usa SQL) debe dar lo mismo que multiplicar.

    [Theory]
    [InlineData(new[] { 0.10, -0.10 }, -0.01)]
    [InlineData(new[] { 0.10, -0.10, 0.05 }, 0.0395)]
    public void SumaDeLogaritmos_EquivaleACompound(double[] returns, double expected)
    {
        var sumOfLogs = returns.Sum(Compounding.ToLogGrowth);

        var result = Compounding.FromLogGrowth(sumOfLogs);

        Assert.Equal(expected, result, Precision);
        Assert.Equal(Compounding.Compound(returns), result, Precision);
    }

    [Fact]
    public void RestaDeAcumulados_DaElRetornoDelSubrango()
    {
        // Así calcula SQL un rango: Cum[fin] - Cum[antes del inicio].
        double[] daily = { 0.02, 0.10, -0.10, 0.05, -0.03 };
        var cumulative = new double[daily.Length];
        var acc = 0.0;
        for (var i = 0; i < daily.Length; i++)
        {
            acc += Compounding.ToLogGrowth(daily[i]);
            cumulative[i] = acc;
        }

        // Rango días 2..4 (índices 1..3) = [+10 %, -10 %, +5 %]
        var result = Compounding.FromLogGrowth(cumulative[3] - cumulative[0]);

        Assert.Equal(0.0395, result, Precision);
    }

    // Bordes.

    [Fact]
    public void Compound_SinDias_DaCero()
    {
        Assert.Equal(0.0, Compounding.Compound(Array.Empty<double>()));
    }

    [Fact]
    public void PortfolioReturn_ValorInicialCero_DaNull()
    {
        var result = Compounding.PortfolioReturn(new[] { new PositionDay(0m, 0m) });

        Assert.Null(result);
    }

    [Theory]
    [InlineData(-1.0)]
    [InlineData(-1.5)]
    public void ToLogGrowth_PerdidaTotalOMayor_Lanza(double r)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => Compounding.ToLogGrowth(r));
    }
}
