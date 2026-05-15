#!/bin/bash
# Run JOB through Balsa (Yang et al., SIGMOD 2022).
#
# Balsa learns a query optimizer without expert demos and emits its decisions as
# pg_hint_plan hints. Repo: https://github.com/balsa-project/balsa
#
# Setup (one-time, CPU-only — no CUDA needed):
#   git clone https://github.com/balsa-project/balsa ~/balsa
#   cd ~/balsa
#   # Build PG14 with pg_hint_plan and the Balsa patch:
#   ./scripts/build_pg.sh   # produces ~/balsa/inst/
#   ./scripts/init_db.sh    # initializes cluster on PORT 5502
#   # CPU-only PyTorch (training will be slower than on GPU):
#   pip install --index-url https://download.pytorch.org/whl/cpu torch
#   pip install -r ~/balsa/requirements.txt
#   export CUDA_VISIBLE_DEVICES=""
#   # Train Balsa on JOB-train split (hours on CPU):
#   python -m balsa.train --workload=job --device=cpu
#   # Balsa writes per-query hints to ~/balsa/hints/job/<query>.hint
#
# After training, this script applies hints + measures.

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

export PGPORT="${BALSA_PORT:-5502}"
export PGDATA="${BALSA_PGDATA:-$HOME/balsa_pgdata}"
export INSTDIR="${BALSA_INSTDIR:-$HOME/balsa/inst/bin}"
DB="${1:-imdb}"
ITERS="${2:-$ITERS}"
METHOD="balsa"
HINTS_DIR="${BALSA_HINTS_DIR:-$HOME/balsa/hints/job}"
PSQL="$INSTDIR/psql -p $PGPORT -d $DB -U $PGUSER -X -q"

mkdir -p "$PLANS_DIR/$METHOD" "$RESULTS_DIR" "$LOG_DIR"
OUT_CSV="$RESULTS_DIR/${METHOD}_job.csv"
csv_header > "$OUT_CSV"

if [ ! -d "$HINTS_DIR" ]; then
    echo "ERROR: $HINTS_DIR not found. Train Balsa first to generate hints." >&2
    exit 1
fi

balsa_run_once() {
    local qf="$1" hint_file="$2"
    {
        echo "LOAD 'pg_hint_plan';"
        echo "SET statement_timeout = ${STATEMENT_TIMEOUT_MS};"
        echo "\\timing on"
        [ -f "$hint_file" ] && cat "$hint_file"
        sed 's/;[[:space:]]*$//' "$qf"
        echo ";"
    } | $PSQL -f - 2>/dev/null \
        | awk '/^Time: / { print $2; exit }'
}

balsa_save_explain() {
    local qf="$1" hint_file="$2" name plan_file
    name="$(basename "$qf" .sql)"
    plan_file="$PLANS_DIR/$METHOD/${name}.plan"
    {
        echo "LOAD 'pg_hint_plan';"
        echo "SET statement_timeout = ${STATEMENT_TIMEOUT_MS};"
        [ -f "$hint_file" ] && cat "$hint_file"
        echo "EXPLAIN"
        sed 's/;[[:space:]]*$//' "$qf"
        echo ";"
    } | $PSQL -f - > "$plan_file" 2>&1
}

queries=("$QUERY_FILES"/*.sql)
total=${#queries[@]}
for idx in "${!queries[@]}"; do
    qf="${queries[$idx]}"
    name="$(basename "$qf" .sql)"
    hint="$HINTS_DIR/${name}.hint"
    n=$((idx + 1))
    echo "[$n/$total] $name"

    balsa_save_explain "$qf" "$hint"
    for i in $(seq 1 "$ITERS"); do
        ms=$(balsa_run_once "$qf" "$hint")
        echo "$name,$i,${ms:-NA}" >> "$OUT_CSV"
    done
done

echo "Plans -> $PLANS_DIR/$METHOD"
echo "Times -> $OUT_CSV"
