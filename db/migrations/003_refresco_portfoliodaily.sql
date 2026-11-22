-- 003: procedimiento de refresco de dbo.PortfolioDaily y carga inicial.
--
-- Uso:
--   * Llegó un día nuevo o se corrigió un día pasado D de un portafolio:
--       EXEC dbo.usp_RefreshPortfolioDaily @PortfolioId = 7, @FromDate = 'D';
--   * Recalcular todo:
--       EXEC dbo.usp_RefreshPortfolioDaily @PortfolioId = NULL, @FromDate = '19000101';
--
-- Qué hace: borra las filas del portafolio desde @FromDate, vuelve a agregar
-- esos días desde dbo.PositionDaily (seek sobre IX_PositionDaily_Portfolio_Date)
-- y recalcula los acumulados partiendo del último día anterior a @FromDate.
-- Un portafolio tiene como máximo ~2.600 días, así que corregir un día antiguo
-- reescribe a lo más esas filas: es barato y deja todo consistente.
USE FinPerf;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RefreshPortfolioDaily
    @PortfolioId INT = NULL,  -- NULL = todos los portafolios
    @FromDate    DATE         -- primer día que cambió
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @FromDate IS NULL
        THROW 50001, N'@FromDate es obligatorio.', 1;

    -- La tabla de hechos guarda DATETIME: se compara contra un DATETIME para
    -- que el predicado sea sargable (sin funciones sobre la columna).
    DECLARE @FromDateTime DATETIME = CAST(@FromDate AS DATETIME);

    -- 1) Acumulados del último día anterior a @FromDate, por portafolio.
    CREATE TABLE #Base (
        PortfolioId  INT           NOT NULL PRIMARY KEY,
        CumLogReturn FLOAT         NOT NULL,
        CumPnL       DECIMAL(19,4) NOT NULL,
        DayNumber    INT           NOT NULL
    );

    INSERT INTO #Base (PortfolioId, CumLogReturn, CumPnL, DayNumber)
    SELECT p.PortfolioId,
           ISNULL(b.CumLogReturn, 0),
           ISNULL(b.CumPnL, 0),
           ISNULL(b.DayNumber, 0)
    FROM dbo.Portfolio p
    OUTER APPLY (SELECT TOP (1) d.CumLogReturn, d.CumPnL, d.DayNumber
                 FROM dbo.PortfolioDaily d
                 WHERE d.PortfolioId = p.PortfolioId
                   AND d.AsOfDate < @FromDate
                 ORDER BY d.AsOfDate DESC) b
    WHERE @PortfolioId IS NULL OR p.PortfolioId = @PortfolioId;

    -- 2) Totales por portafolio y día desde @FromDate (idea 3: sumar y
    --    después dividir). La división se hace en FLOAT: dividir dos
    --    DECIMAL(38,4) deja solo 6 decimales y pierde precisión.
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

    BEGIN TRANSACTION;

    DELETE d
    FROM dbo.PortfolioDaily d
    WHERE (@PortfolioId IS NULL OR d.PortfolioId = @PortfolioId)
      AND d.AsOfDate >= @FromDate
    OPTION (RECOMPILE);

    INSERT INTO dbo.PortfolioDaily
        (PortfolioId, AsOfDate, MarketValueBegin, NetFlows, PnL, MarketValueEnd,
         DailyReturn, LogReturn, CumLogReturn, CumPnL, DayNumber)
    SELECT x.PortfolioId, x.AsOfDate, x.MarketValueBegin, x.NetFlows, x.PnL, x.MarketValueEnd,
           x.DailyReturn,
           x.LogReturn,
           b.CumLogReturn + SUM(ISNULL(x.LogReturn, 0)) OVER (PARTITION BY x.PortfolioId ORDER BY x.AsOfDate
                                                               ROWS UNBOUNDED PRECEDING),
           b.CumPnL       + SUM(x.PnL)                 OVER (PARTITION BY x.PortfolioId ORDER BY x.AsOfDate
                                                               ROWS UNBOUNDED PRECEDING),
           b.DayNumber    + ROW_NUMBER()               OVER (PARTITION BY x.PortfolioId ORDER BY x.AsOfDate)
    FROM (
        SELECT r.*,
               -- LOG(1 + r) solo está definido si r > -1 (no se perdió todo).
               CASE WHEN r.DailyReturn > -1 THEN LOG(1 + r.DailyReturn) END AS LogReturn
        FROM (
            SELECT d.*,
                   CASE WHEN d.MarketValueBegin <> 0
                        THEN CAST(d.PnL AS FLOAT) / CAST(d.MarketValueBegin AS FLOAT)
                   END AS DailyReturn
            FROM #Daily d
        ) r
    ) x
    JOIN #Base b ON b.PortfolioId = x.PortfolioId;

    COMMIT TRANSACTION;
END;
GO

-- Carga inicial (solo si la tabla está vacía).
IF NOT EXISTS (SELECT 1 FROM dbo.PortfolioDaily)
    EXEC dbo.usp_RefreshPortfolioDaily @PortfolioId = NULL, @FromDate = '19000101';
GO
