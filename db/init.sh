#!/bin/bash
set -euo pipefail

SQLCMD=(/opt/mssql-tools18/bin/sqlcmd -S sqlserver -U sa -P "$MSSQL_SA_PASSWORD" -C -b)

EXISTS=$("${SQLCMD[@]}" -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = 'FinPerf';" | tr -d '[:space:]')

if [ "$EXISTS" = "1" ]; then
  echo "La base FinPerf ya existe; no se vuelve a cargar."
  exit 0
fi

echo "Creando esquema y datos (puede tardar varios minutos)..."
"${SQLCMD[@]}" -i /scripts/01_schema_y_datos.sql
"${SQLCMD[@]}" -i /scripts/02_procedimiento_actual.sql
echo "Base FinPerf lista."
