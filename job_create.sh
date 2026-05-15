#!/bin/bash
# Create JOB database on the current my_postgres9 build (no extensions).
# Expects:
#   - my_postgres9 built and installed at INSTDIR
#   - PGDATA cluster initialized at vacuum_stats9 and running on PORT 5499
#   - JOB CSVs under $QUERY_DIR/csv

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

pg_ensure_up

DB="${1:-imdb}"

"$INSTDIR/psql" -p "$PGPORT" -U "$PGUSER" postgres \
    -c "DROP DATABASE IF EXISTS $DB"
"$INSTDIR/psql" -p "$PGPORT" -U "$PGUSER" postgres \
    -c "CREATE DATABASE $DB"

"$INSTDIR/psql" -p "$PGPORT" -d "$DB" -U "$PGUSER" -f "$QUERY_DIR/schema.sql"
"$INSTDIR/psql" -p "$PGPORT" -d "$DB" -U "$PGUSER" \
    -v datadir="'$QUERY_DIR'" -f "$QUERY_DIR/copy.sql"
"$INSTDIR/psql" -p "$PGPORT" -d "$DB" -U "$PGUSER" -f "$QUERY_DIR/fkindexes.sql"

"$INSTDIR/psql" -p "$PGPORT" -d "$DB" -U "$PGUSER" -c "VACUUM ANALYZE"

echo "JOB database '$DB' created on port $PGPORT, PGDATA=$PGDATA"
