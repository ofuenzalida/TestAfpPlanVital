-- Medición ANTES de las migraciones (o contra la versión _Legacy después).
-- Ejecutar con: scripts/medir.sh antes
-- El plan de ejecución real se obtiene en SSMS/Azure Data Studio con
-- "Include Actual Execution Plan" (Ctrl+M) corriendo el mismo EXEC.
USE FinPerf;
GO
SET NOCOUNT ON;
GO

-- Verificación de la idea 1 sobre los datos: PnL = MVE - MVB - NetFlows.
-- (Se tolera 1 unidad en el 4º decimal por el redondeo del script de carga.)
SELECT COUNT_BIG(*) AS FilasTotales,
       SUM(CASE WHEN ABS(PnL - (MarketValueEnd - MarketValueBegin - NetFlows)) > 0.0001
                THEN 1 ELSE 0 END) AS FilasQueNoCuadran
FROM dbo.PositionDaily;
GO

DBCC DROPCLEANBUFFERS;  -- caché fría (solo en desarrollo)
GO
SET STATISTICS IO, TIME ON;
GO
DECLARE @proc SYSNAME = CASE WHEN OBJECT_ID('dbo.usp_GetPerformance_Legacy') IS NOT NULL
                             THEN N'dbo.usp_GetPerformance_Legacy'
                             ELSE N'dbo.usp_GetPerformance' END;
PRINT CONCAT('== Fría: ', @proc, ' @PortfolioId = 7, @Year = 2023');
EXEC @proc @PortfolioId = 7, @Year = 2023;
GO
DECLARE @proc SYSNAME = CASE WHEN OBJECT_ID('dbo.usp_GetPerformance_Legacy') IS NOT NULL
                             THEN N'dbo.usp_GetPerformance_Legacy'
                             ELSE N'dbo.usp_GetPerformance' END;
PRINT CONCAT('== Caliente: ', @proc, ' @PortfolioId = 7, @Year = 2023');
EXEC @proc @PortfolioId = 7, @Year = 2023;
GO
SET STATISTICS IO, TIME OFF;
GO
