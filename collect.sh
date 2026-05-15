#!/bin/bash
# Aggregate per-iter results from results/<method>_job.csv into a wide CSV
# suitable for plotting slides 34 (latency on JOB) and 37 (worst/best ratio).
#
# Output: results/job_aggregate.csv
#   columns: query, plain_pg_median_ms, plain_pg_p95_ms, bao_median_ms, ...
#
# Usage: ./collect.sh

set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

mkdir -p "$RESULTS_DIR"
OUT="$RESULTS_DIR/job_aggregate.csv"

methods=()
for f in "$RESULTS_DIR"/*_job.csv; do
    [ -f "$f" ] || continue
    base="$(basename "$f" _job.csv)"
    methods+=("$base")
done

if [ "${#methods[@]}" -eq 0 ]; then
    echo "No results/*_job.csv found." >&2
    exit 1
fi

# Build a python aggregator inline (awk for percentile is awkward)
python3 - <<PY
import csv, glob, os, statistics
from collections import defaultdict

results_dir = "$RESULTS_DIR"
methods = sorted(
    os.path.basename(p).removesuffix("_job.csv")
    for p in glob.glob(os.path.join(results_dir, "*_job.csv"))
)
data = defaultdict(lambda: defaultdict(list))  # data[query][method] = [ms,...]

for m in methods:
    with open(os.path.join(results_dir, f"{m}_job.csv")) as fh:
        r = csv.DictReader(fh)
        for row in r:
            try:
                ms = float(row["exec_ms"])
            except (TypeError, ValueError):
                continue
            data[row["query"]][m].append(ms)

queries = sorted(data.keys())
header = ["query"]
for m in methods:
    header += [f"{m}_median_ms", f"{m}_p95_ms", f"{m}_min_ms", f"{m}_max_ms", f"{m}_n"]

out_path = os.path.join(results_dir, "job_aggregate.csv")
with open(out_path, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(header)
    for q in queries:
        row = [q]
        for m in methods:
            xs = data[q].get(m, [])
            if not xs:
                row += ["", "", "", "", 0]
                continue
            xs_sorted = sorted(xs)
            n = len(xs_sorted)
            p95 = xs_sorted[max(0, int(round(0.95 * (n - 1))))]
            row += [
                f"{statistics.median(xs):.3f}",
                f"{p95:.3f}",
                f"{min(xs):.3f}",
                f"{max(xs):.3f}",
                n,
            ]
        w.writerow(row)

print(f"Wrote {out_path}  ({len(queries)} queries, {len(methods)} methods: {methods})")
PY
