-- 001: índice de soporte sobre la tabla de hechos.
--
-- Hoy el único índice es la PK sobre PositionDailyId (IDENTITY), que no sirve
-- para ningún filtro real: toda consulta por portafolio/fecha recorre las ~5,2M
-- filas. Este índice permite buscar por (PortfolioId, AsOfDate) y cubre las
-- columnas que se agregan, así que nunca hace falta volver a la tabla base.
--
-- Se usa para:
--   * la carga inicial y el refresco incremental de dbo.PortfolioDaily
--     (migración 002/003), que agregan un portafolio desde una fecha;
--   * cualquier consulta ad hoc sobre posiciones de un portafolio y rango.
--
-- No se cambia el clustered (PK) para no reescribir la tabla en producción ni
-- romper a quien dependa de PositionDailyId; el nonclustered cubriente da el
-- mismo beneficio para estas lecturas.
USE FinPerf;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_PositionDaily_Portfolio_Date'
                 AND object_id = OBJECT_ID('dbo.PositionDaily'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_PositionDaily_Portfolio_Date
        ON dbo.PositionDaily (PortfolioId, AsOfDate)
        INCLUDE (MarketValueBegin, NetFlows, PnL, MarketValueEnd)
        WITH (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
END;
GO
