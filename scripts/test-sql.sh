#!/bin/bash
# Ejecuta los tests SQL de db/tests/ contra la base del docker-compose.
# Cada test corre en una transacción que se revierte; no deja datos.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for f in db/tests/*.sql; do
  echo "== $f"
  out=$(docker compose run --rm --no-deps --entrypoint /opt/mssql-tools18/bin/sqlcmd db-init \
    -S sqlserver -U sa -P "${SA_PASSWORD:-FinPerf_Dev_2026!}" -C -b -W -s '|' -i "/scripts/tests/$(basename "$f")")
  echo "$out"
  if echo "$out" | grep -q 'FALLA'; then status=1; fi
done
exit $status
