#!/bin/bash
# Captura los planes de ejecución reales y los guarda como .sqlplan
# (se abren en SSMS o Azure Data Studio). Ver db/bench/03_planes.sql.
set -euo pipefail
cd "$(dirname "$0")/.."
out=docs/mediciones/planes
mkdir -p "$out"
docker compose run --rm --no-deps --entrypoint /opt/mssql-tools18/bin/sqlcmd db-init \
  -S sqlserver -U sa -P "${SA_PASSWORD:-FinPerf_Dev_2026!}" -C -b -y 0 \
  -i /scripts/bench/03_planes.sql > "$out/raw.txt"
python3 - "$out" <<'PY'
import re, sys, pathlib
out = pathlib.Path(sys.argv[1])
name, n = None, 0
for line in (out / "raw.txt").read_text(encoding="utf-8", errors="replace").splitlines():
    m = re.match(r"@@PLAN (\S+)", line)
    if m:
        name, n = m.group(1), 0
        continue
    i = line.find("<ShowPlanXML")
    if name and i >= 0:
        n += 1
        (out / f"{name}_{n}.sqlplan").write_text(line[i:].strip(), encoding="utf-8")
        print(f"{name}_{n}.sqlplan")
PY
rm "$out/raw.txt"
