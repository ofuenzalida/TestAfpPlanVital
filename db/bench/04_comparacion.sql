-- Comparación con el mismo criterio para ambos procedimientos: tiempo total
-- de EXEC (reloj de pared medido dentro de SQL Server, plan ya compilado y
-- caché caliente), varias repeticiones.
-- En los dos casos los resultados se envían al cliente igual que en producción.
-- El "antes" se mide con el índice de la migración 001 deshabilitado (la tabla
-- queda como estaba: solo la PK) y después se reconstruye.
-- Ejecutar con: scripts/medir.sh comparacion
USE FinPerf;
GO
SET NOCOUNT ON;
GO
CREATE TABLE #t (Proc_ SYSNAME, Run INT, Ms DECIMAL(12,3));
DECLARE @i INT, @t0 DATETIME2(7);

ALTER INDEX IX_PositionDaily_Portfolio_Date ON dbo.PositionDaily DISABLE;

-- Calentamiento (compila y carga páginas en memoria)
EXEC dbo.usp_GetPerformance_Legacy @PortfolioId = 7, @Year = 2023;

SET @i = 1;
WHILE @i <= 3
BEGIN
    SET @t0 = SYSDATETIME();
    EXEC dbo.usp_GetPerformance_Legacy @PortfolioId = 7, @Year = 2023;
    INSERT INTO #t VALUES ('usp_GetPerformance_Legacy', @i, DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0);
    SET @i += 1;
END;

ALTER INDEX IX_PositionDaily_Portfolio_Date ON dbo.PositionDaily REBUILD;

EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;  -- calentamiento

-- Una ejecución del procedimiento nuevo dura menos que la resolución del reloj
-- en este entorno, así que se mide un bloque de 200 ejecuciones seguidas y se
-- divide: el promedio por ejecución es más fiable que medir una a una.
SET @t0 = SYSDATETIME();
SET @i = 1;
WHILE @i <= 200
BEGIN
    EXEC dbo.usp_GetPerformance @PortfolioId = 7, @Year = 2023;
    SET @i += 1;
END;
DECLARE @total DECIMAL(12,3) = DATEDIFF(MICROSECOND, @t0, SYSDATETIME()) / 1000.0;
SELECT 'usp_GetPerformance (nuevo)' AS Procedimiento, 200 AS Ejecuciones,
       @total AS TotalMs, CAST(@total / 200 AS DECIMAL(12,3)) AS PromedioMsPorEjecucion;

SELECT DISTINCT Proc_ AS Procedimiento, -- antes, una a una
       COUNT(*) OVER (PARTITION BY Proc_)                                   AS Ejecuciones,
       MIN(Ms) OVER (PARTITION BY Proc_)                                    AS MinMs,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Ms) OVER (PARTITION BY Proc_) AS MedianaMs,
       MAX(Ms) OVER (PARTITION BY Proc_)                                    AS MaxMs
FROM #t;
GO
