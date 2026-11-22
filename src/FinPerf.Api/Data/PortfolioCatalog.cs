using Microsoft.Extensions.Caching.Memory;

namespace FinPerf.Api.Data;

/// <summary>
/// Lista de portafolios con su rango de fechas con datos, en caché de memoria.
///
/// Qué se cachea: solo esta lista (20 filas). La consultan todas las peticiones
/// para validar que el portafolio exista y que las fechas estén dentro del rango
/// con datos, y cambia como mucho una vez al día (cuando se carga un día nuevo).
///
/// Cómo se invalida: expira sola a los <see cref="Ttl"/> minutos, y
/// <see cref="Invalidate"/> permite vaciarla de inmediato (por ejemplo, desde el
/// proceso que refresca dbo.PortfolioDaily). Los resultados de rendimiento NO se
/// cachean: cada consulta lee unas pocas páginas por clave y tarda ~1 ms, así que
/// cachearlos agregaría riesgo de servir datos viejos tras una corrección sin
/// una ganancia real.
/// </summary>
public sealed class PortfolioCatalog(IPerformanceRepository repository, IMemoryCache cache)
{
    public static readonly TimeSpan Ttl = TimeSpan.FromMinutes(5);
    private const string CacheKey = "portfolios";

    public async Task<IReadOnlyList<PortfolioRow>> GetAllAsync(CancellationToken ct)
    {
        if (cache.TryGetValue(CacheKey, out IReadOnlyList<PortfolioRow>? cached) && cached is not null)
        {
            return cached;
        }

        var portfolios = await repository.GetPortfoliosAsync(ct);
        cache.Set(CacheKey, portfolios, Ttl);
        return portfolios;
    }

    public async Task<PortfolioRow?> FindAsync(int portfolioId, CancellationToken ct)
    {
        var all = await GetAllAsync(ct);
        return all.FirstOrDefault(p => p.PortfolioId == portfolioId);
    }

    public void Invalidate() => cache.Remove(CacheKey);
}
