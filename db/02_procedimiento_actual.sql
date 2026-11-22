USE FinPerf;
GO

CREATE OR ALTER FUNCTION dbo.fn_PortfolioDailyReturn (@PortfolioId INT, @Date DATETIME)
RETURNS FLOAT
AS
BEGIN
    DECLARE @r FLOAT;

    SELECT @r = SUM(PnL) / SUM(MarketValueBegin)
    FROM dbo.PositionDaily
    WHERE PortfolioId = @PortfolioId
      AND CONVERT(VARCHAR(10), AsOfDate, 120) = CONVERT(VARCHAR(10), @Date, 120);

    RETURN @r;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetPerformance
    @PortfolioId INT,
    @Year        INT
AS
BEGIN
    -- Retorno y P&L por mes
    SELECT d.Mes,
           SUM(dbo.fn_PortfolioDailyReturn(@PortfolioId, d.Dia)) AS RetornoMes,
           (SELECT SUM(p.PnL)
            FROM dbo.PositionDaily p
            WHERE p.PortfolioId = @PortfolioId
              AND YEAR(p.AsOfDate) = @Year
              AND MONTH(p.AsOfDate) = d.Mes)                      AS PnLMes
    FROM (SELECT DISTINCT CONVERT(DATE, AsOfDate) AS Dia,
                          MONTH(AsOfDate)         AS Mes
          FROM dbo.PositionDaily
          WHERE PortfolioId = @PortfolioId
            AND YEAR(AsOfDate) = @Year) d
    GROUP BY d.Mes
    ORDER BY d.Mes;

    -- Acumulado del año
    SELECT SUM(DailyReturn) AS RetornoYTD,
           SUM(PnL)         AS PnLYTD
    FROM dbo.PositionDaily
    WHERE PortfolioId = @PortfolioId
      AND YEAR(AsOfDate) = @Year;
END;
GO

-- Uso: EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;
