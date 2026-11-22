-- 006: corrige dos defectos de las migraciones 003 y 004 (se deja como
-- migración nueva para no reescribir scripts ya aplicados).
--
-- 1) Pérdida del 100 %. LOG(1 + r) no existe si r <= -1, y 003 guardaba
--    LogReturn = NULL, que la suma acumulada trataba como 0: el día de pérdida
--    total "desaparecía" y [-100 %, +10 %] daba +10 % en vez de -100 %.
--    Ahora se cuenta, de forma acumulada, cuántos días tuvieron r <= -1
--    (CumTotalLossDays). Si un rango contiene al menos uno, el factor
--    (1 + r) de ese día es 0 (o negativo), el producto queda anulado y el
--    retorno del rango es -100 %. Un r < -100 % (perder más que el valor
--    inicial) solo es posible con apalancamiento; se trata igual, como
--    pérdida total.
--
-- 2) Refrescos simultáneos. En 003 la lectura de la base acumulada y la
--    agregación ocurrían antes de abrir la transacción: dos refrescos en
--    paralelo podían calcular con datos viejos y el último en escribir
--    pisaba al otro. Ahora todo el refresco corre dentro de una transacción
--    que toma primero un bloqueo de aplicación exclusivo (sp_getapplock),
--    así que los refrescos se ejecutan de a uno y cada uno parte de lo que
--    dejó el anterior. Cada refresco dura milisegundos, así que serializar
--    no es un cuello de botella.
USE FinPerf;
GO

IF COL_LENGTH('dbo.PortfolioDaily', 'CumTotalLossDays') IS NULL
    ALTER TABLE dbo.PortfolioDaily
        ADD CumTotalLossDays INT NOT NULL
            CONSTRAINT DF_PortfolioDaily_CumTotalLossDays DEFAULT (0);
GO

CREATE OR ALTER PROCEDURE dbo.usp_RefreshPortfolioDaily
    @PortfolioId INT = NULL,  -- NULL = todos los portafolios
    @FromDate    DATE         -- primer día que cambió
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- ante cualquier error se revierte todo y se libera el bloqueo

    IF @FromDate IS NULL
        THROW 50001, N'@FromDate es obligatorio.', 1;

    DECLARE @FromDateTime DATETIME = CAST(@FromDate AS DATETIME);
    DECLARE @lock INT;

    BEGIN TRANSACTION;

    -- Un solo refresco a la vez. El bloqueo pertenece a la transacción y se
    -- libera solo con el COMMIT o el ROLLBACK.
    EXEC @lock = sys.sp_getapplock
        @Resource    = N'FinPerf.usp_RefreshPortfolioDaily',
        @LockMode    = N'Exclusive',
        @LockOwner   = N'Transaction',
        @LockTimeout = 60000;

    IF @lock < 0
        THROW 50002, N'No se pudo obtener el bloqueo de refresco (timeout o deadlock).', 1;

    -- 1) Acumulados del último día anterior a @FromDate (ya dentro del bloqueo).
    CREATE TABLE #Base (
        PortfolioId      INT           NOT NULL PRIMARY KEY,
        CumLogReturn     FLOAT         NOT NULL,
        CumPnL           DECIMAL(19,4) NOT NULL,
        DayNumber        INT           NOT NULL,
        CumTotalLossDays INT           NOT NULL
    );

    INSERT INTO #Base (PortfolioId, CumLogReturn, CumPnL, DayNumber, CumTotalLossDays)
    SELECT p.PortfolioId,
           ISNULL(b.CumLogReturn, 0),
           ISNULL(b.CumPnL, 0),
           ISNULL(b.DayNumber, 0),
           ISNULL(b.CumTotalLossDays, 0)
    FROM dbo.Portfolio p
    OUTER APPLY (SELECT TOP (1) d.CumLogReturn, d.CumPnL, d.DayNumber, d.CumTotalLossDays
                 FROM dbo.PortfolioDaily d
                 WHERE d.PortfolioId = p.PortfolioId
                   AND d.AsOfDate < @FromDate
                 ORDER BY d.AsOfDate DESC) b
    WHERE @PortfolioId IS NULL OR p.PortfolioId = @PortfolioId;

    -- 2) Totales por portafolio y día desde @FromDate (idea 3), dividiendo en FLOAT.
    SELECT pd.PortfolioId,
           CAST(pd.AsOfDate AS DATE)  AS AsOfDate,
           SUM(pd.MarketValueBegin)   AS MarketValueBegin,
           SUM(pd.NetFlows)           AS NetFlows,
           SUM(pd.PnL)                AS PnL,
           SUM(pd.MarketValueEnd)     AS MarketValueEnd
    INTO #Daily
    FROM dbo.PositionDaily pd
    WHERE (@PortfolioId IS NULL OR pd.PortfolioId = @PortfolioId)
      AND pd.AsOfDate >= @FromDateTime
    GROUP BY pd.PortfolioId, CAST(pd.AsOfDate AS DATE)
    OPTION (RECOMPILE);

    -- 3) Reemplazo de las filas desde @FromDate.
    DELETE d
    FROM dbo.PortfolioDaily d
    WHERE (@PortfolioId IS NULL OR d.PortfolioId = @PortfolioId)
      AND d.AsOfDate >= @FromDate
    OPTION (RECOMPILE);

    INSERT INTO dbo.PortfolioDaily
        (PortfolioId, AsOfDate, MarketValueBegin, NetFlows, PnL, MarketValueEnd,
         DailyReturn, LogReturn, CumLogReturn, CumPnL, DayNumber, CumTotalLossDays)
    SELECT x.PortfolioId, x.AsOfDate, x.MarketValueBegin, x.NetFlows, x.PnL, x.MarketValueEnd,
           x.DailyReturn,
           x.LogReturn,
           b.CumLogReturn + SUM(ISNULL(x.LogReturn, 0)) OVER w,
           b.CumPnL       + SUM(x.PnL)                 OVER w,
           b.DayNumber    + ROW_NUMBER()               OVER (PARTITION BY x.PortfolioId ORDER BY x.AsOfDate),
           b.CumTotalLossDays + SUM(x.IsTotalLoss)     OVER w
    FROM (
        SELECT r.*,
               CASE WHEN r.DailyReturn > -1 THEN LOG(1 + r.DailyReturn) END   AS LogReturn,
               CASE WHEN r.DailyReturn <= -1 THEN 1 ELSE 0 END                 AS IsTotalLoss
        FROM (
            SELECT d.*,
                   CASE WHEN d.MarketValueBegin <> 0
                        THEN CAST(d.PnL AS FLOAT) / CAST(d.MarketValueBegin AS FLOAT)
                   END AS DailyReturn
            FROM #Daily d
        ) r
    ) x
    JOIN #Base b ON b.PortfolioId = x.PortfolioId
    WINDOW w AS (PARTITION BY x.PortfolioId ORDER BY x.AsOfDate ROWS UNBOUNDED PRECEDING);

    COMMIT TRANSACTION;
END;
GO

-- (b) Rango: ahora también devuelve TotalLossDays y fuerza -100 % si hay alguno.
CREATE OR ALTER FUNCTION dbo.tvf_PerformanceRange
(
    @PortfolioId INT,
    @From        DATE,
    @To          DATE
)
RETURNS TABLE
AS
RETURN
SELECT @PortfolioId                                                  AS PortfolioId,
       @From                                                         AS FromDate,
       @To                                                           AS ToDate,
       f.AsOfDate                                                    AS FirstDataDate,
       e.AsOfDate                                                    AS LastDataDate,
       ISNULL(e.DayNumber - ISNULL(b.DayNumber, 0), 0)               AS DaysWithData,
       ISNULL(e.CumTotalLossDays - ISNULL(b.CumTotalLossDays, 0), 0) AS TotalLossDays,
       e.CumLogReturn - ISNULL(b.CumLogReturn, 0)                    AS SumLogReturn,
       CASE WHEN e.CumTotalLossDays - ISNULL(b.CumTotalLossDays, 0) > 0 THEN -1.0
            ELSE EXP(e.CumLogReturn - ISNULL(b.CumLogReturn, 0)) - 1
       END                                                           AS [Return],
       e.CumPnL - ISNULL(b.CumPnL, 0)                                AS PnL
FROM (VALUES (1)) AS one(x)
OUTER APPLY (SELECT TOP (1) d.AsOfDate, d.CumLogReturn, d.CumPnL, d.DayNumber, d.CumTotalLossDays
             FROM dbo.PortfolioDaily d
             WHERE d.PortfolioId = @PortfolioId
               AND d.AsOfDate >= @From
               AND d.AsOfDate <= @To
             ORDER BY d.AsOfDate DESC) e
OUTER APPLY (SELECT TOP (1) d.CumLogReturn, d.CumPnL, d.DayNumber, d.CumTotalLossDays
             FROM dbo.PortfolioDaily d
             WHERE d.PortfolioId = @PortfolioId
               AND d.AsOfDate < @From
             ORDER BY d.AsOfDate DESC) b
OUTER APPLY (SELECT TOP (1) d.AsOfDate
             FROM dbo.PortfolioDaily d
             WHERE d.PortfolioId = @PortfolioId
               AND d.AsOfDate >= @From
               AND d.AsOfDate <= @To
             ORDER BY d.AsOfDate) f;
GO

-- (a) Resumen: misma lógica, expone TotalLossDays.
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
       r.TotalLossDays,
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

-- (c) Mensual: cuenta los días de pérdida total de cada mes.
CREATE OR ALTER FUNCTION dbo.tvf_PerformanceMonthly
(
    @PortfolioId INT,
    @From        DATE,
    @To          DATE
)
RETURNS TABLE
AS
RETURN
SELECT YEAR(d.AsOfDate)                                        AS [Year],
       MONTH(d.AsOfDate)                                       AS [Month],
       MIN(d.AsOfDate)                                         AS FirstDataDate,
       MAX(d.AsOfDate)                                         AS LastDataDate,
       COUNT(*)                                                AS DaysWithData,
       SUM(CASE WHEN d.DailyReturn <= -1 THEN 1 ELSE 0 END)    AS TotalLossDays,
       SUM(ISNULL(d.LogReturn, 0))                             AS SumLogReturn,
       CASE WHEN SUM(CASE WHEN d.DailyReturn <= -1 THEN 1 ELSE 0 END) > 0 THEN -1.0
            ELSE EXP(SUM(ISNULL(d.LogReturn, 0))) - 1
       END                                                     AS [Return],
       SUM(d.PnL)                                              AS PnL
FROM dbo.PortfolioDaily d
WHERE d.PortfolioId = @PortfolioId
  AND d.AsOfDate >= @From
  AND d.AsOfDate <= @To
GROUP BY YEAR(d.AsOfDate), MONTH(d.AsOfDate);
GO

-- Recalcular todo con la nueva columna.
EXEC dbo.usp_RefreshPortfolioDaily @PortfolioId = NULL, @FromDate = '19000101';
GO
