#!/bin/bash
set -euo pipefail

SQLCMD=(/opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -b)

# Filas que genera 01_schema_y_datos.sql: 20 portafolios x 100 instrumentos x 2.609 días.
EXPECTED_ROWS=5218000

# Estado de la base:
#   0 = no existe
#   1 = carga completa (marcada en dbo.DataLoad)
#   2 = carga completa de una versión anterior de este script (sin marca): se marca
#   3 = existe pero la carga quedó a medias (se interrumpió): se recrea
STATE=$("${SQLCMD[@]}" -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @state INT = 0, @rows BIGINT = 0;
IF DB_ID('FinPerf') IS NOT NULL
BEGIN
    SET @state = 3;
    IF OBJECT_ID('FinPerf.dbo.DataLoad', 'U') IS NOT NULL
        SET @state = 1;
    ELSE IF OBJECT_ID('FinPerf.dbo.PositionDaily', 'U') IS NOT NULL
        AND OBJECT_ID('FinPerf.dbo.fn_PortfolioDailyReturn') IS NOT NULL
    BEGIN
        EXEC sp_executesql N'SELECT @rows = COUNT_BIG(*) FROM FinPerf.dbo.PositionDaily',
                           N'@rows BIGINT OUTPUT', @rows OUTPUT;
        IF @rows = $EXPECTED_ROWS SET @state = 2;
    END
END
SELECT @state;" | tr -d '[:space:]')

mark_complete() {
  "${SQLCMD[@]}" -d FinPerf -Q "
    IF OBJECT_ID('dbo.DataLoad', 'U') IS NULL
        CREATE TABLE dbo.DataLoad (CompletedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME());
    INSERT INTO dbo.DataLoad DEFAULT VALUES;"
}

case "$STATE" in
  1)
    echo "La base FinPerf ya existe y su carga está completa; no se vuelve a cargar."
    exit 0
    ;;
  2)
    echo "La base FinPerf está completa ($EXPECTED_ROWS filas); se registra la marca de carga."
    mark_complete
    exit 0
    ;;
  3)
    echo "La base FinPerf existe pero la carga anterior quedó incompleta; se elimina y se vuelve a cargar."
    "${SQLCMD[@]}" -Q "ALTER DATABASE FinPerf SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE FinPerf;"
    ;;
  0)
    ;;
  *)
    echo "No se pudo determinar el estado de la base (respuesta: '$STATE')." >&2
    exit 1
    ;;
esac

echo "Creando esquema y datos (puede tardar varios minutos)..."
"${SQLCMD[@]}" -i /scripts/01_schema_y_datos.sql
"${SQLCMD[@]}" -i /scripts/02_procedimiento_actual.sql
# La marca se escribe solo al final: si algo falla antes, el próximo arranque
# detecta la carga incompleta y la rehace.
mark_complete
echo "Base FinPerf lista."
