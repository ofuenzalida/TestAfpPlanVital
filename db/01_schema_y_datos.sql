CREATE DATABASE FinPerf;
GO
ALTER DATABASE FinPerf SET RECOVERY SIMPLE;
GO
USE FinPerf;
GO

CREATE TABLE dbo.Portfolio (
    PortfolioId   INT           NOT NULL PRIMARY KEY,
    Name          NVARCHAR(100) NOT NULL,
    InceptionDate DATE          NOT NULL,
    BaseCurrency  CHAR(3)       NOT NULL
);

CREATE TABLE dbo.Instrument (
    InstrumentId INT         NOT NULL PRIMARY KEY,
    Ticker       VARCHAR(20) NOT NULL,
    AssetClass   VARCHAR(20) NOT NULL
);

-- Tabla de hechos tal como existe hoy.
-- No modifiques este script: tus cambios van en db/migrations/.
CREATE TABLE dbo.PositionDaily (
    PositionDailyId  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    PortfolioId      INT           NOT NULL,
    InstrumentId     INT           NOT NULL,
    AsOfDate         DATETIME      NOT NULL,
    MarketValueBegin DECIMAL(19,4) NOT NULL,
    NetFlows         DECIMAL(19,4) NOT NULL,
    PnL              DECIMAL(19,4) NOT NULL,
    MarketValueEnd   DECIMAL(19,4) NOT NULL,
    DailyReturn      FLOAT         NOT NULL
);
GO

INSERT INTO dbo.Portfolio (PortfolioId, Name, InceptionDate, BaseCurrency)
SELECT n, CONCAT(N'Portafolio ', n), '2015-01-01', 'CLP'
FROM (SELECT TOP (20) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS n
      FROM sys.all_objects) t;

INSERT INTO dbo.Instrument (InstrumentId, Ticker, AssetClass)
SELECT n, CONCAT('TCK', n),
       CASE n % 3 WHEN 0 THEN 'Equity' WHEN 1 THEN 'FixedIncome' ELSE 'Cash' END
FROM (SELECT TOP (100) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS n
      FROM sys.all_objects) t;

-- Calendario de días hábiles 2015-2024 (el 1900-01-01 fue lunes)
SELECT d
INTO #Cal
FROM (SELECT TOP (3653)
             DATEADD(DAY, CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) - 1,
                     CAST('2015-01-01' AS DATE)) AS d
      FROM sys.all_objects a CROSS JOIN sys.all_objects b) c
WHERE DATEDIFF(DAY, '19000101', d) % 7 < 5;

-- Un portafolio por iteración para acotar el log de transacciones
DECLARE @p INT = 1;
WHILE @p <= 20
BEGIN
    INSERT INTO dbo.PositionDaily WITH (TABLOCK)
        (PortfolioId, InstrumentId, AsOfDate, MarketValueBegin, NetFlows,
         PnL, MarketValueEnd, DailyReturn)
    SELECT @p, x.InstrumentId, x.d, x.mvb, x.flow,
           x.mvb * x.r,
           x.mvb * (1 + x.r) + x.flow,
           x.r
    FROM (
        SELECT i.InstrumentId, c.d,
               CAST(100000 + h.h1 % 900000 AS DECIMAL(19,4))          AS mvb,
               (CAST(h.h2 % 2001 AS FLOAT) - 1000) / 50000 + 0.0002   AS r,
               CASE WHEN h.h3 % 100 = 0
                    THEN CAST(h.h3 % 20001 AS DECIMAL(19,4)) - 10000
                    ELSE 0 END                                        AS flow
        FROM #Cal c
        CROSS JOIN dbo.Instrument i
        CROSS APPLY (SELECT
            CAST(CAST(HASHBYTES('MD5', CONCAT('m', @p, '|', i.InstrumentId, '|', c.d)) AS BINARY(4)) AS BIGINT) AS h1,
            CAST(CAST(HASHBYTES('MD5', CONCAT('r', @p, '|', i.InstrumentId, '|', c.d)) AS BINARY(4)) AS BIGINT) AS h2,
            CAST(CAST(HASHBYTES('MD5', CONCAT('f', @p, '|', i.InstrumentId, '|', c.d)) AS BINARY(4)) AS BIGINT) AS h3
        ) h
    ) x;

    SET @p += 1;
END;

DROP TABLE #Cal;
GO
