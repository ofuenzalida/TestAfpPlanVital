-- 002: tabla pre-agregada por portafolio y día.
--
-- Una fila por portafolio y día hábil (20 x 2.609 = ~52 mil filas en vez de
-- 5,2 millones). Guarda los totales del día (idea 3: se suma P&L y valor
-- inicial de todos los instrumentos y recién después se divide) y además
-- columnas acumuladas desde el inicio del portafolio:
--
--   CumLogReturn = SUM(LOG(1 + r)) hasta ese día (idea 4 en forma aditiva)
--   CumPnL       = SUM(PnL) hasta ese día (idea 1)
--   DayNumber    = número correlativo del día con datos (1, 2, 3, ...)
--
-- Con eso, el retorno y P&L de cualquier rango [From, To] salen de dos
-- lecturas puntuales por la clave clustered:
--
--   Retorno = EXP(Cum[To] - Cum[From - 1]) - 1
--   P&L     = CumPnL[To] - CumPnL[From - 1]
--
-- AsOfDate es DATE (en la tabla de hechos es DATETIME, ver diagnóstico).
USE FinPerf;
GO

IF OBJECT_ID('dbo.PortfolioDaily', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PortfolioDaily (
        PortfolioId      INT           NOT NULL,
        AsOfDate         DATE          NOT NULL,
        MarketValueBegin DECIMAL(19,4) NOT NULL,  -- suma de los instrumentos
        NetFlows         DECIMAL(19,4) NOT NULL,
        PnL              DECIMAL(19,4) NOT NULL,
        MarketValueEnd   DECIMAL(19,4) NOT NULL,
        DailyReturn      FLOAT         NULL,      -- SUM(PnL) / SUM(MVB); NULL si MVB = 0
        LogReturn        FLOAT         NULL,      -- LOG(1 + DailyReturn); NULL si no está definido
        CumLogReturn     FLOAT         NOT NULL,  -- acumulado de LogReturn (NULL cuenta como 0)
        CumPnL           DECIMAL(19,4) NOT NULL,
        DayNumber        INT           NOT NULL,
        CONSTRAINT PK_PortfolioDaily PRIMARY KEY CLUSTERED (PortfolioId, AsOfDate),
        CONSTRAINT FK_PortfolioDaily_Portfolio FOREIGN KEY (PortfolioId)
            REFERENCES dbo.Portfolio (PortfolioId)
    );
END;
GO
