-- 005: reemplazo de dbo.usp_GetPerformance (lo usa hoy la pantalla Razor).
--
-- Mantiene el mismo contrato (parámetros y columnas de salida) para no romper
-- la pantalla actual, pero corrige el cálculo y lee de dbo.PortfolioDaily.
-- La versión original se conserva como dbo.usp_GetPerformance_Legacy para
-- poder comparar resultados y tiempos (db/bench/). Se puede borrar después.
USE FinPerf;
GO

IF OBJECT_ID('dbo.usp_GetPerformance_Legacy', 'P') IS NULL
   AND OBJECT_ID('dbo.usp_GetPerformance', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.usp_GetPerformance', 'usp_GetPerformance_Legacy';
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetPerformance
    @PortfolioId INT,
    @Year        INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @From DATE = DATEFROMPARTS(@Year, 1, 1),
            @To   DATE = DATEFROMPARTS(@Year, 12, 31);

    -- Retorno (compuesto) y P&L por mes
    SELECT m.[Month]  AS Mes,
           m.[Return] AS RetornoMes,
           m.PnL      AS PnLMes
    FROM dbo.tvf_PerformanceMonthly(@PortfolioId, @From, @To) m
    ORDER BY m.[Month];

    -- Acumulado del año (compuesto sobre el retorno diario del portafolio)
    SELECT r.[Return] AS RetornoYTD,
           r.PnL      AS PnLYTD
    FROM dbo.tvf_PerformanceRange(@PortfolioId, @From, @To) r;
END;
GO
