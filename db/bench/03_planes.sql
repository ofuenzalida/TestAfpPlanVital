-- Planes de ejecución reales (SET STATISTICS XML) antes y después.
-- Ejecutar con: scripts/planes.sh  -> docs/mediciones/planes/*.sqlplan
--
-- Para el "antes" sin recrear la base se deshabilita temporalmente el índice
-- de la migración 001: con el índice deshabilitado la tabla queda igual que
-- antes de los cambios (solo la PK). Al final se reconstruye.
USE FinPerf;
GO
SET NOCOUNT ON;
GO
ALTER INDEX IX_PositionDaily_Portfolio_Date ON dbo.PositionDaily DISABLE;
GO
PRINT '@@PLAN antes_usp_GetPerformance';
SET STATISTICS XML ON;
EXEC dbo.usp_GetPerformance_Legacy @PortfolioId = 7, @Year = 2023;
SET STATISTICS XML OFF;
GO
ALTER INDEX IX_PositionDaily_Portfolio_Date ON dbo.PositionDaily REBUILD;
GO
PRINT '@@PLAN despues_usp_GetPerformance';
SET STATISTICS XML ON;
EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;
SET STATISTICS XML OFF;
GO
PRINT '@@PLAN despues_resumen';
SET STATISTICS XML ON;
SELECT Period, FromDate, ToDate, DaysWithData, [Return], PnL
FROM dbo.tvf_PerformanceSummary(7, '2023-08-15') ORDER BY SortOrder;
SET STATISTICS XML OFF;
GO
PRINT '@@PLAN despues_rango';
SET STATISTICS XML ON;
SELECT DaysWithData, [Return], PnL FROM dbo.tvf_PerformanceRange(7, '2018-03-01', '2023-08-15');
SET STATISTICS XML OFF;
GO
PRINT '@@PLAN despues_mensual';
SET STATISTICS XML ON;
SELECT [Year], [Month], [Return], PnL
FROM dbo.tvf_PerformanceMonthly(7, '2015-01-01', '2024-12-31') ORDER BY [Year], [Month];
SET STATISTICS XML OFF;
GO
