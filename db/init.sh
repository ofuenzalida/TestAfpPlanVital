#!/bin/bash
set -euo pipefail

SQLCMD=(/opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -b)

# Filas que genera 01_schema_y_datos.sql: 20 portafolios x 100 instrumentos x 2.609 días.
EXPECTED_ROWS=5218000

# FINPERF_RECREATE=1 autoriza eliminar y recargar una base en estado ambiguo.
RECREATE="${FINPERF_RECREATE:-0}"

# Estado de la base:
#   0 = no existe                                   -> se carga
#   1 = carga completa (marcada en dbo.DataLoad)    -> no se toca
#   2 = completa pero sin marca (versión anterior de este script): exactamente
#       las filas esperadas y el procedimiento original -> se marca, no se toca
#   3 = carga interrumpida, sin ambigüedad: solo existen las tablas del script
#       01, nunca se migró y tiene MENOS filas de las esperadas -> se recarga
#   4 = ambiguo: sin marca y con algo que la carga no crea (más filas de las
#       esperadas, migraciones aplicadas u otras tablas). Puede tener datos
#       que no se pueden regenerar -> se detiene, salvo FINPERF_RECREATE=1
STATE=$("${SQLCMD[@]}" -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @state INT = 0, @rows BIGINT = 0, @otherTables INT = 0;
IF DB_ID('FinPerf') IS NOT NULL
BEGIN
    IF OBJECT_ID('FinPerf.dbo.DataLoad', 'U') IS NOT NULL
        SET @state = 1;
    ELSE
    BEGIN
        IF OBJECT_ID('FinPerf.dbo.PositionDaily', 'U') IS NOT NULL
            EXEC sp_executesql N'SELECT @rows = COUNT_BIG(*) FROM FinPerf.dbo.PositionDaily',
                               N'@rows BIGINT OUTPUT', @rows OUTPUT;
        SELECT @otherTables = COUNT(*) FROM FinPerf.sys.tables
        WHERE name NOT IN ('Portfolio', 'Instrument', 'PositionDaily');

        IF @rows = $EXPECTED_ROWS AND @otherTables = 0
           AND OBJECT_ID('FinPerf.dbo.fn_PortfolioDailyReturn') IS NOT NULL
            SET @state = 2;
        ELSE IF @rows = $EXPECTED_ROWS AND OBJECT_ID('FinPerf.dbo.SchemaMigration', 'U') IS NOT NULL
            SET @state = 2;  -- completa y ya migrada con una versión anterior de este script
        ELSE IF @rows < $EXPECTED_ROWS AND @otherTables = 0
            SET @state = 3;
        ELSE
            SET @state = 4;
    END
END
SELECT CONCAT(@state, '|', @rows, '|', @otherTables);" | tr -d '[:space:]')

IFS='|' read -r STATE ROWS OTHER_TABLES <<< "$STATE"

mark_complete() {
  "${SQLCMD[@]}" -d FinPerf -Q "
    IF OBJECT_ID('dbo.DataLoad', 'U') IS NULL
        CREATE TABLE dbo.DataLoad (CompletedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME());
    INSERT INTO dbo.DataLoad DEFAULT VALUES;"
}

drop_database() {
  "${SQLCMD[@]}" -Q "ALTER DATABASE FinPerf SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE FinPerf;"
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
    echo "La base FinPerf quedó a medias ($ROWS de $EXPECTED_ROWS filas, sin migraciones ni otras tablas): se elimina y se vuelve a cargar."
    drop_database
    ;;
  4)
    if [ "$RECREATE" = "1" ]; then
      echo "La base FinPerf está en un estado ambiguo; FINPERF_RECREATE=1, así que se elimina y se vuelve a cargar."
      drop_database
    else
      cat >&2 <<EOF
La base FinPerf existe pero no tiene la marca de carga completa y su estado es ambiguo:
  filas en PositionDaily: $ROWS (se esperan $EXPECTED_ROWS)
  tablas que la carga no crea: $OTHER_TABLES
Puede contener datos que no se regeneran, así que no se elimina automáticamente.
Para eliminarla y recargarla:  FINPERF_RECREATE=1 docker compose up db-init
EOF
      exit 1
    fi
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
