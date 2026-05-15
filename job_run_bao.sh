#!/bin/bash
# Run JOB through Bao (Marcus et al., SIGMOD 2021).
#
# Bao = PostgreSQL extension `pg_bao` + Python ML service (BaoForPostgreSQL).
# Bao ships its own PostgreSQL fork (it modifies the planner). You CANNOT
# load pg_bao into the vanilla my_postgres9 build directly.
#
# Setup (one-time, CPU-only — no CUDA needed):
#   git clone https://github.com/learnedsystems/BaoForPostgreSQL ~/BaoForPostgreSQL
#   # Build Bao's PG fork (see BaoForPostgreSQL/README.md):
#   cd ~/BaoForPostgreSQL/pg_extension && make USE_PGXS=1 install
#   # Initialize cluster on a SEPARATE port (e.g. 5500) and PGDATA:
#   initdb -D ~/bao_pgdata
#   pg_ctl -D ~/bao_pgdata -o "-p 5500" start
#   psql -p 5500 postgres -c "CREATE EXTENSION pg_bao"
#   # Install CPU-only PyTorch for the Bao server:
#   pip install --index-url https://download.pytorch.org/whl/cpu torch
#   pip install -r ~/BaoForPostgreSQL/bao_server/requirements.txt
#   # Force CPU even if a GPU is present:
#   export CUDA_VISIBLE_DEVICES=""
#   cd ~/BaoForPostgreSQL/bao_server && python main.py
#
# Then re-run job_create.sh against PGPORT=5500 to load JOB into Bao's cluster.
#
# This script measures Bao's plans the same way as plain PG: EXPLAIN + timed run.
# It does NOT include Bao's inference time directly — Bao injects hints inside
# the planner; client-side wallclock captures total cost (planning + exec).

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

# Override cluster — Bao uses its own
export PGPORT="${BAO_PORT:-5500}"
export PGDATA="${BAO_PGDATA:-$HOME/bao_pgdata}"
export INSTDIR="${BAO_INSTDIR:-$HOME/BaoForPostgreSQL/pg_extension/inst/bin}"
DB="${1:-imdb}"
ITERS="${2:-$ITERS}"
METHOD="bao"
PSQL="$INSTDIR/psql -p $PGPORT -d $DB -U $PGUSER -X -q"

mkdir -p "$PLANS_DIR/$METHOD" "$RESULTS_DIR" "$LOG_DIR"
OUT_CSV="$RESULTS_DIR/${METHOD}_job.csv"
csv_header > "$OUT_CSV"

# Sanity: Bao server reachable? Without it, pg_bao falls back to the default
# PG planner and we'd silently log default-PG numbers as "Bao". Fail loudly.
if ! curl -fsS -m 2 -o /dev/null http://localhost:9381/ \
        && ! (exec 3<>/dev/tcp/localhost/9381) 2>/dev/null; then
    echo "ERROR: Bao server (http://localhost:9381) not reachable. Start bao_server first." >&2
    exit 1
fi
exec 3>&- 2>/dev/null || true

queries=("$QUERY_FILES"/*.sql)
total=${#queries[@]}

for idx in "${!queries[@]}"; do
    qf="${queries[$idx]}"
    name="$(basename "$qf" .sql)"
    n=$((idx + 1))
    echo "[$n/$total] $name"

    # Plain EXPLAIN — Bao influences plan via planner_hook
    save_plain_explain "$qf" "$METHOD"

    for i in $(seq 1 "$ITERS"); do
        ms=$(run_query_once "$qf")
        echo "$name,$i,${ms:-NA}" >> "$OUT_CSV"
    done
done

echo "Plans -> $PLANS_DIR/$METHOD"
echo "Times -> $OUT_CSV"
