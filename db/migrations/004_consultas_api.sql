-- 004: consultas que usa la API (Parte 1, punto 4).
--
-- Todas leen dbo.PortfolioDaily por su clave clustered (PortfolioId, AsOfDate).
-- Se implementan como funciones inline (TVF): el optimizador las expande
-- dentro de la consulta que las llama, aceptan parámetros y se pueden
-- combinar (el resumen reutiliza la de rango).
--
-- Convención de rangos: [@From, @To] ambos inclusive, sobre los días que
-- tienen datos. Si @From cae en fin de semana se toma el primer día hábil
-- siguiente; si @To cae en fin de semana, el último día hábil anterior.
--
-- Las funciones devuelven SumLogReturn (= SUM(LOG(1 + r)) del rango) y
-- también [Return] = EXP(SumLogReturn) - 1 para quien consulte desde SQL.
-- La API usa SumLogReturn y hace la conversión en C# (lógica aislada y testeada).
USE FinPerf;
GO

-- Portafolios con el rango de fechas que tiene datos (para validar en la API).
-- MIN/MAX sobre la columna líder del índice clustered = dos seeks por portafolio.
CREATE OR ALTER VIEW dbo.vw_PortfolioInfo
AS
SELECT p.PortfolioId,
       p.Name,
       p.InceptionDate,
       p.BaseCurrency,
       (SELECT MIN(d.AsOfDate) FROM dbo.PortfolioDaily d WHERE d.PortfolioId = p.PortfolioId) AS FirstDataDate,
       (SELECT MAX(d.AsOfDate) FROM dbo.PortfolioDaily d WHERE d.PortfolioId = p.PortfolioId) AS LastDataDate
FROM dbo.Portfolio p;
GO

-- (b) Acumulado de un rango @From–@To: tres lecturas puntuales.
CREATE OR ALTER FUNCTION dbo.tvf_PerformanceRange
(
    @PortfolioId INT,
    @From        DATE,
    @To          DATE
)
RETURNS TABLE
AS
RETURN
SELECT @PortfolioId                                     AS PortfolioId,
       @From                                            AS FromDate,
       @To                                              AS ToDate,
       f.AsOfDate                                       AS FirstDataDate,
       e.AsOfDate                                       AS LastDataDate,
       ISNULL(e.DayNumber - ISNULL(b.DayNumber, 0), 0)  AS DaysWithData,
       e.CumLogReturn - ISNULL(b.CumLogReturn, 0)       AS SumLogReturn,
       EXP(e.CumLogReturn - ISNULL(b.CumLogReturn, 0)) - 1 AS [Return],
       e.CumPnL - ISNULL(b.CumPnL, 0)                   AS PnL
FROM (VALUES (1)) AS one(x)
-- último día con datos dentro del rango
OUTER APPLY (SELECT TOP (1) d.AsOfDate, d.CumLogReturn, d.CumPnL, d.DayNumber
             FROM dbo.PortfolioDaily d
             WHERE d.PortfolioId = @PortfolioId
               AND d.AsOfDate >= @From
               AND d.AsOfDate <= @To
             ORDER BY d.AsOfDate DESC) e
-- último día con datos antes del rango (base del acumulado)
OUTER APPLY (SELECT TOP (1) d.CumLogReturn, d.CumPnL, d.DayNumber
             FROM dbo.PortfolioDaily d
             WHERE d.PortfolioId = @PortfolioId
               AND d.AsOfDate < @From
             ORDER BY d.AsOfDate DESC) b
-- primer día con datos dentro del rango (informativo)
OUTER APPLY (SELECT TOP (1) d.AsOfDate
             FROM dbo.PortfolioDaily d
             WHERE d.PortfolioId = @PortfolioId
               AND d.AsOfDate >= @From
               AND d.AsOfDate <= @To
             ORDER BY d.AsOfDate) f;
GO

-- (a) Resumen MTD, QTD, YTD e ITD a una fecha de corte.
-- Cada periodo empieza como muy temprano en la fecha de inicio del portafolio.
CREATE OR ALTER FUNCTION dbo.tvf_PerformanceSummary
(
    @PortfolioId INT,
    @AsOf        DATE
)
RETURNS TABLE
AS
RETURN
SELECT per.Period,
       per.SortOrder,
       r.FromDate,
       r.ToDate,
       r.FirstDataDate,
       r.LastDataDate,
       r.DaysWithData,
       r.SumLogReturn,
       r.[Return],
       r.PnL
FROM dbo.Portfolio pf
CROSS APPLY (VALUES
    ('MTD', 1, DATEFROMPARTS(YEAR(@AsOf), MONTH(@AsOf), 1)),
    ('QTD', 2, DATEFROMPARTS(YEAR(@AsOf), ((MONTH(@AsOf) - 1) / 3) * 3 + 1, 1)),
    ('YTD', 3, DATEFROMPARTS(YEAR(@AsOf), 1, 1)),
    ('ITD', 4, pf.InceptionDate)
) AS per(Period, SortOrder, FromDate)
CROSS APPLY dbo.tvf_PerformanceRange(
    pf.PortfolioId,
    CASE WHEN per.FromDate < pf.InceptionDate THEN pf.InceptionDate ELSE per.FromDate END,
    @AsOf) AS r
WHERE pf.PortfolioId = @PortfolioId;
GO

-- (c) Retorno y P&L de cada mes de un rango. Los meses de los extremos se
-- recortan al rango pedido. Lee como máximo ~2.600 filas contiguas.
CREATE OR ALTER FUNCTION dbo.tvf_PerformanceMonthly
(
    @PortfolioId INT,
    @From        DATE,
    @To          DATE
)
RETURNS TABLE
AS
RETURN
SELECT YEAR(d.AsOfDate)                      AS [Year],
       MONTH(d.AsOfDate)                     AS [Month],
       MIN(d.AsOfDate)                       AS FirstDataDate,
       MAX(d.AsOfDate)                       AS LastDataDate,
       COUNT(*)                              AS DaysWithData,
       SUM(ISNULL(d.LogReturn, 0))           AS SumLogReturn,
       EXP(SUM(ISNULL(d.LogReturn, 0))) - 1  AS [Return],
       SUM(d.PnL)                            AS PnL
FROM dbo.PortfolioDaily d
WHERE d.PortfolioId = @PortfolioId
  AND d.AsOfDate >= @From
  AND d.AsOfDate <= @To
GROUP BY YEAR(d.AsOfDate), MONTH(d.AsOfDate);
GO
