#!/bin/bash
# Shared variables and helpers for JOB benchmark scripts.

# PostgreSQL install (current my_postgres9 build)
INSTDIR="${INSTDIR:-/home/alena/my_postgres9/my/inst/bin}"

# Cluster
export PGDATA="${PGDATA:-/home/alena/my_postgres9/vacuum_stats9}"
export PGPORT="${PGPORT:-5499}"
export PGUSER="${PGUSER:-$(whoami)}"
export PGDATABASE="${PGDATABASE:-postgres}"

# Benchmark
QUERY_DIR="${QUERY_DIR:-/home/alena/source}"
QUERY_FILES="${QUERY_FILES:-$QUERY_DIR/queries}"

# Output
BENCH_ROOT="${BENCH_ROOT:-/home/alena/min_job}"
PLANS_DIR="${PLANS_DIR:-$BENCH_ROOT/plans}"
RESULTS_DIR="${RESULTS_DIR:-$BENCH_ROOT/results}"
LOG_DIR="${LOG_DIR:-$BENCH_ROOT/logs}"

# Per-query repetitions and timeout
ITERS="${ITERS:-5}"
STATEMENT_TIMEOUT_MS="${STATEMENT_TIMEOUT_MS:-600000}" # 10 minutes

PSQL="$INSTDIR/psql -p $PGPORT -d $PGDATABASE -U $PGUSER -X -q"

# Ensure server is up; restart only if not running.
pg_ensure_up() {
    if ! "$INSTDIR/pg_isready" -p "$PGPORT" -q; then
        "$INSTDIR/pg_ctl" -w -D "$PGDATA" -l "$BENCH_ROOT/logfile.log" start
    fi
}

# Write EXPLAIN (cost-only) for query $1 into plans dir for method $2.
save_plain_explain() {
    local query_file="$1" method="$2"
    local name plan_file
    name="$(basename "$query_file" .sql)"
    plan_file="$PLANS_DIR/$method/${name}.plan"
    mkdir -p "$PLANS_DIR/$method"
    {
        echo "SET statement_timeout = ${STATEMENT_TIMEOUT_MS};"
        echo "EXPLAIN"
        sed 's/;[[:space:]]*$//' "$query_file"
        echo ";"
    } | $PSQL -f - > "$plan_file" 2>&1
}

# Run query $1 once, print elapsed ms to stdout.
# Uses \timing on; greps the first 'Time: X ms' line.
run_query_once() {
    local query_file="$1"
    {
        echo "SET statement_timeout = ${STATEMENT_TIMEOUT_MS};"
        echo "\\timing on"
        sed 's/;[[:space:]]*$//' "$query_file"
        echo ";"
    } | $PSQL -f - 2>/dev/null \
        | awk '/^Time: / { print $2; exit }'
}

# CSV header for results
csv_header() { echo "query,iter,exec_ms"; }
