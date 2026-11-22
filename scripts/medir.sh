#!/bin/bash
# Ejecuta un script de medición y guarda la salida (incluye STATISTICS IO/TIME).
#   scripts/medir.sh antes    -> docs/mediciones/antes.txt
#   scripts/medir.sh despues  -> docs/mediciones/despues.txt
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  antes)   file=01_antes.sql ;;
  despues) file=02_despues.sql ;;
  comparacion) file=04_comparacion.sql ;;
  *) echo "Uso: $0 antes|despues|comparacion" >&2; exit 1 ;;
esac

mkdir -p docs/mediciones
docker compose run --rm --no-deps --entrypoint /opt/mssql-tools18/bin/sqlcmd db-init \
  -S sqlserver -U sa -P "${SA_PASSWORD:-FinPerf_Dev_2026!}" -C -b -W -s '|' \
  -i "/scripts/bench/$file" | tee "docs/mediciones/$1.txt"
