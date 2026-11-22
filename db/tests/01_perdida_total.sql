-- Test de la pérdida del 100 % (hallazgo de revisión). Todo ocurre dentro de
-- una transacción que se revierte al final: no deja datos.
-- Ejecutar: scripts/test-sql.sh
USE FinPerf;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

INSERT INTO dbo.Portfolio (PortfolioId, Name, InceptionDate, BaseCurrency)
VALUES (9999, N'Test pérdida total', '2030-01-01', 'CLP');

-- Día 1: r = -100 %; día 2: r = +10 %; día 3: r = +5 %.
INSERT INTO dbo.PositionDaily (PortfolioId, InstrumentId, AsOfDate, MarketValueBegin, NetFlows, PnL, MarketValueEnd, DailyReturn)
VALUES (9999, 1, '2030-01-01', 1000, 0, -1000,    0, -1.0),
       (9999, 1, '2030-01-02', 1000, 0,   100, 1100,  0.10),
       (9999, 1, '2030-01-03', 1000, 0,    50, 1050,  0.05);

EXEC dbo.usp_RefreshPortfolioDaily @PortfolioId = 9999, @FromDate = '2030-01-01';

DECLARE @r1 FLOAT = (SELECT [Return] FROM dbo.tvf_PerformanceRange(9999, '2030-01-01', '2030-01-02'));
DECLARE @r2 FLOAT = (SELECT [Return] FROM dbo.tvf_PerformanceRange(9999, '2030-01-02', '2030-01-03'));
DECLARE @r3 FLOAT = (SELECT [Return] FROM dbo.tvf_PerformanceMonthly(9999, '2030-01-01', '2030-01-31'));
DECLARE @r4 FLOAT = (SELECT [Return] FROM dbo.tvf_PerformanceSummary(9999, '2030-01-03') WHERE Period = 'ITD');

SELECT 'Rango [-100 %, +10 %] = -100 %'                AS Caso, @r1 AS Obtenido,
       CASE WHEN @r1 = -1 THEN 'OK' ELSE 'FALLA' END AS Resultado
UNION ALL
SELECT 'Rango posterior [+10 %, +5 %] = +15,5 %', @r2,
       CASE WHEN ABS(@r2 - 0.155) < 1e-12 THEN 'OK' ELSE 'FALLA' END
UNION ALL
SELECT 'Mes con pérdida total = -100 %', @r3,
       CASE WHEN @r3 = -1 THEN 'OK' ELSE 'FALLA' END
UNION ALL
SELECT 'ITD con pérdida total = -100 %', @r4,
       CASE WHEN @r4 = -1 THEN 'OK' ELSE 'FALLA' END;

ROLLBACK TRANSACTION;
GO
