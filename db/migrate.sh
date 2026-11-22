#!/bin/bash
# Aplica en orden los scripts de db/migrations/ que aún no se hayan aplicado.
# Registra cada script aplicado en dbo.SchemaMigration, así que es seguro
# ejecutarlo varias veces.
set -euo pipefail

SQLCMD=(/opt/mssql-tools18/bin/sqlcmd -S "${SQL_HOST:-sqlserver}" -U sa -P "$MSSQL_SA_PASSWORD" -C -b)

"${SQLCMD[@]}" -d FinPerf -Q "
IF OBJECT_ID('dbo.SchemaMigration', 'U') IS NULL
    CREATE TABLE dbo.SchemaMigration (
        FileName  NVARCHAR(200) NOT NULL PRIMARY KEY,
        AppliedAt DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
    );"

for f in /scripts/migrations/*.sql; do
  name=$(basename "$f")
  applied=$("${SQLCMD[@]}" -d FinPerf -h -1 -W -Q \
    "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.SchemaMigration WHERE FileName = N'$name';" | tr -d '[:space:]')
  if [ "$applied" = "1" ]; then
    echo "= $name (ya aplicada)"
    continue
  fi
  echo "> Aplicando $name"
  "${SQLCMD[@]}" -i "$f"
  "${SQLCMD[@]}" -d FinPerf -Q "INSERT INTO dbo.SchemaMigration (FileName) VALUES (N'$name');"
done

echo "Migraciones al día."
