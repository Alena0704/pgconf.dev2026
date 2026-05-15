#!/bin/bash
# Run JOB on plain PostgreSQL (current my_postgres9 build, no extensions).
#   - Saves EXPLAIN (plain, cost-only) plans to plans/plain_pg/
#   - Saves per-iter exec times to results/plain_pg_job.csv
#
# Usage: ./job_run.sh [database] [iters]

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

DB="${1:-imdb}"
ITERS="${2:-$ITERS}"
METHOD="plain_pg"

export PGDATABASE="$DB"
PSQL="$INSTDIR/psql -p $PGPORT -d $DB -U $PGUSER -X -q"

mkdir -p "$PLANS_DIR/$METHOD" "$RESULTS_DIR" "$LOG_DIR"

OUT_CSV="$RESULTS_DIR/${METHOD}_job.csv"
csv_header > "$OUT_CSV"

pg_ensure_up

queries=("$QUERY_FILES"/*.sql)
total=${#queries[@]}

for idx in "${!queries[@]}"; do
    qf="${queries[$idx]}"
    name="$(basename "$qf" .sql)"
    n=$((idx + 1))
    echo "[$n/$total] $name"

    # 1. Save plain EXPLAIN (one shot, no analyze)
    save_plain_explain "$qf" "$METHOD"

    # 2. Time N runs
    for i in $(seq 1 "$ITERS"); do
        ms=$(run_query_once "$qf")
        ms="${ms:-NA}"
        echo "$name,$i,$ms" >> "$OUT_CSV"
    done
done

echo "Plans -> $PLANS_DIR/$METHOD"
echo "Times -> $OUT_CSV"
