-- Medición DESPUÉS de las migraciones.
-- Ejecutar con: scripts/medir.sh despues
USE FinPerf;
GO
SET NOCOUNT ON;
GO

DBCC DROPCLEANBUFFERS;  -- caché fría (solo en desarrollo)
GO
SET STATISTICS IO, TIME ON;
GO

PRINT '== (a) Resumen MTD/QTD/YTD/ITD, portafolio 7, corte 2023-08-15 (fría)';
SELECT Period, FromDate, ToDate, DaysWithData, [Return], PnL
FROM dbo.tvf_PerformanceSummary(7, '2023-08-15')
ORDER BY SortOrder;
GO

PRINT '== (a) Resumen (caliente)';
SELECT Period, FromDate, ToDate, DaysWithData, [Return], PnL
FROM dbo.tvf_PerformanceSummary(7, '2023-08-15')
ORDER BY SortOrder;
GO

PRINT '== (b) Rango 2018-03-01 a 2023-08-15';
SELECT FirstDataDate, LastDataDate, DaysWithData, [Return], PnL
FROM dbo.tvf_PerformanceRange(7, '2018-03-01', '2023-08-15');
GO

PRINT '== (c) Mensual 2015-01-01 a 2024-12-31 (120 meses)';
SELECT [Year], [Month], DaysWithData, [Return], PnL
FROM dbo.tvf_PerformanceMonthly(7, '2015-01-01', '2024-12-31')
ORDER BY [Year], [Month];
GO

PRINT '== usp_GetPerformance nuevo, @PortfolioId = 7, @Year = 2023 (primera ejecución)';
EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;
GO

-- Mismo criterio que la medición "Caliente" de 01_antes.sql: la línea
-- "SQL Server Execution Times" que sigue al EXEC es el total del procedimiento.
PRINT '== usp_GetPerformance nuevo (caliente, ejecución completa)';
EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;
GO

SET STATISTICS IO, TIME OFF;
GO

-- Control de consistencia: el YTD por acumulados (tvf_PerformanceRange) debe
-- coincidir con componer los retornos diarios uno a uno.
PRINT '== Control: acumulado O(1) vs composición día a día (2023)';
SELECT r.[Return]                                   AS RetornoPorAcumulados,
       (SELECT EXP(SUM(LOG(1 + d.DailyReturn))) - 1
        FROM dbo.PortfolioDaily d
        WHERE d.PortfolioId = 7 AND d.AsOfDate BETWEEN '2023-01-01' AND '2023-12-31') AS RetornoDiaADia,
       r.PnL                                        AS PnLPorAcumulados,
       (SELECT SUM(p.PnL) FROM dbo.PositionDaily p
        WHERE p.PortfolioId = 7 AND p.AsOfDate >= '2023-01-01' AND p.AsOfDate < '2024-01-01') AS PnLDesdeHechos
FROM dbo.tvf_PerformanceRange(7, '2023-01-01', '2023-12-31') r;
GO
