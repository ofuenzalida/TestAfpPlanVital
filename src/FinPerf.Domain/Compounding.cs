namespace FinPerf.Domain;

/// <summary>
/// Reglas de cálculo de retornos (ideas 2, 3 y 4 del enunciado), sin dependencias
/// de base de datos ni de ASP.NET para poder testearlas de forma aislada.
/// Los retornos se expresan como fracción: 0,05 = 5 %.
/// </summary>
public static class Compounding
{
    /// <summary>
    /// Idea 3: retorno diario del portafolio. Se suman primero el P&amp;L y el valor
    /// inicial de todos los instrumentos y recién después se divide (promedio
    /// ponderado por tamaño, no promedio simple).
    /// Devuelve <c>null</c> si el valor inicial total es 0 (retorno no definido).
    /// </summary>
    public static double? PortfolioReturn(IEnumerable<PositionDay> positions)
    {
        ArgumentNullException.ThrowIfNull(positions);

        decimal totalBegin = 0m, totalPnL = 0m;
        foreach (var p in positions)
        {
            totalBegin += p.MarketValueBegin;
            totalPnL += p.PnL;
        }

        return totalBegin == 0m ? null : (double)totalPnL / (double)totalBegin;
    }

    /// <summary>
    /// Idea 4: retorno acumulado. Los retornos se multiplican:
    /// (1 + r1) × (1 + r2) × … × (1 + rn) − 1. Una secuencia vacía da 0.
    /// Un día con r &lt;= −100 % es una pérdida total: su factor es 0 y el
    /// acumulado queda en −100 % sin importar los días siguientes. (Un r menor
    /// a −100 % solo es posible con apalancamiento; se trata igual.)
    /// </summary>
    public static double Compound(IEnumerable<double> returns)
    {
        ArgumentNullException.ThrowIfNull(returns);

        var growth = 1.0;
        foreach (var r in returns)
        {
            if (r <= TotalLoss)
            {
                return TotalLoss;
            }
            growth *= 1 + r;
        }
        return growth - 1;
    }

    /// <summary>Retorno de una pérdida total: −100 %.</summary>
    public const double TotalLoss = -1.0;

    /// <summary>
    /// Convierte un retorno a su forma logarítmica, LOG(1 + r). En esa forma los
    /// retornos se suman en vez de multiplicarse, que es lo que permite guardarlos
    /// acumulados en SQL (columna CumLogReturn).
    /// </summary>
    public static double ToLogGrowth(double r)
    {
        if (r <= -1)
        {
            throw new ArgumentOutOfRangeException(nameof(r), r,
                "LOG(1 + r) solo está definido para retornos mayores a -100 %.");
        }
        return Math.Log(1 + r);
    }

    /// <summary>
    /// Inversa de <see cref="ToLogGrowth"/> aplicada a una suma de logaritmos:
    /// EXP(Σ LOG(1 + r)) − 1 = retorno compuesto del periodo.
    /// Los días con pérdida total no tienen logaritmo, así que no están en la
    /// suma: se informan aparte en <paramref name="totalLossDays"/> y, si hay
    /// alguno, el periodo completo es −100 %.
    /// </summary>
    public static double FromLogGrowth(double sumOfLogGrowth, int totalLossDays = 0) =>
        totalLossDays > 0 ? TotalLoss : Math.Exp(sumOfLogGrowth) - 1;
}

/// <summary>Valor inicial y P&amp;L de un instrumento en un día.</summary>
public readonly record struct PositionDay(decimal MarketValueBegin, decimal PnL);
