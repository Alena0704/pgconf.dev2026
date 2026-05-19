#!/usr/bin/env python3
"""Per-method per-query e2e: one PNG per algorithm.

Reads plot_data/all_methods.csv (wide format: query, n_rel, <method>_e2e_ms…)
and writes one bar chart per algorithm (PG side-by-side with the method),
log Y-axis, style matching saio_planning_vs_exec.png.

Output: plots/<method>_vs_pg_per_query.png  for each of HyperQO, AlphaJoin,
Bao, Neo, SkinnerDB, MCTS.

Options:
    --src=PATH    override CSV path (default: plot_data/all_methods.csv)
    --min-n=N     only queries with n_rel >= N (default 0)
    --max-n=N     only queries with n_rel <= N (default unlimited)
    --tag=STR     filename suffix override (default derived from filters)
    --horizontal  draw horizontal bars (queries on Y, time on log-X)
    --rows=N      force N subplot rows for vertical layout (default: auto)
    --out-dir=D   output directory (default: plots/)
"""
import csv
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
src = HERE / "plot_data" / "all_methods.csv"
out_dir = HERE / "plots"
min_n = 0
max_n = None
tag_override = None
horizontal = False
force_rows = None

for i, a in enumerate(sys.argv):
    if a.startswith("--src="):       src = Path(a.split("=", 1)[1])
    elif a == "--src" and i + 1 < len(sys.argv):
        src = Path(sys.argv[i + 1])
    elif a.startswith("--min-n="):   min_n = int(a.split("=", 1)[1])
    elif a.startswith("--max-n="):   max_n = int(a.split("=", 1)[1])
    elif a.startswith("--tag="):     tag_override = a.split("=", 1)[1]
    elif a == "--horizontal":        horizontal = True
    elif a.startswith("--rows="):    force_rows = int(a.split("=", 1)[1])
    elif a.startswith("--out-dir="): out_dir = Path(a.split("=", 1)[1])

# (csv-key, display label, colour) — order chosen so the comparison plot
# always pairs the method with PG (blue) on the left.
PG = ("pg", "PostgreSQL", "#1f4e79")
METHODS = [
    ("hq",      "HyperQO",   "#3a7c2f"),
    ("alpha",   "AlphaJoin", "#7a4a1f"),
    ("bao",     "Bao",       "#a35e00"),
    ("neo",     "Neo",       "#6b4f9b"),
    ("skinner", "SkinnerDB", "#1f6f7a"),
    ("mcts",    "MCTS",      "#c14c2f"),
]

if not src.exists():
    print(f"missing source CSV: {src}", file=sys.stderr)
    sys.exit(1)

rows = []
with open(src) as f:
    for r in csv.DictReader(f):
        try:
            n = int(r["n_rel"])
        except (ValueError, KeyError):
            continue
        rec = {"q": r["query"], "n": n}
        for key, _, _ in [PG] + METHODS:
            v = r.get(f"{key}_e2e_ms", "")
            try:
                fv = float(v)
                rec[key] = fv if fv > 0 else None
            except ValueError:
                rec[key] = None
        rows.append(rec)

rows = [r for r in rows if r["n"] >= min_n
        and (max_n is None or r["n"] <= max_n)]
if not rows:
    print("no rows after filtering", file=sys.stderr)
    sys.exit(1)

# Sort by n_rel asc, then by PG e2e asc.
rows.sort(key=lambda r: (r["n"], r.get("pg") or float("inf")))

out_dir.mkdir(parents=True, exist_ok=True)

import math

ROW_MAX = 32  # max queries per subplot row before wrapping

for key, label, colour in METHODS:
    data = [(r, r.get(key)) for r in rows
            if r.get(key) is not None and r.get("pg") is not None]
    if not data:
        print(f"  skip {key}: no comparable rows")
        continue

    n_q = len(data)
    pg_vals_all = [r["pg"] for r, _ in data]
    me_vals_all = [v for _, v in data]

    # geomean / wins / losses across the whole filtered set
    ratios = [me / pg for pg, me in zip(pg_vals_all, me_vals_all) if pg and me]
    gm = (math.exp(sum(math.log(r) for r in ratios) / len(ratios))
          if ratios else float("nan"))
    wins = sum(1 for r in ratios if r < 0.95)
    losses = sum(1 for r in ratios if r > 1.05)

    if horizontal:
        # Single tall figure: queries on Y (smallest n_rel at top), log X for time
        ordered = list(data)  # already sorted by (n_rel asc, pg asc)
        ordered.reverse()      # so smallest n_rel ends up at top of the figure
        labels = [f"{r['q']} (n={r['n']})" for r, _ in ordered]
        pg_vals = [r["pg"] for r, _ in ordered]
        me_vals = [v for _, v in ordered]

        fig_h = max(6, 0.22 * n_q + 1.5)
        fig, ax = plt.subplots(figsize=(10, fig_h))
        y = np.arange(n_q)
        bar_h = 0.4
        ax.barh(y + bar_h / 2, pg_vals, bar_h, color=PG[2],
                edgecolor="black", linewidth=0.15, label="PostgreSQL")
        ax.barh(y - bar_h / 2, me_vals, bar_h, color=colour,
                edgecolor="black", linewidth=0.15, label=label)
        ax.set_xscale("log")
        ax.set_yticks(y)
        ax.set_yticklabels(labels, fontsize=7)
        ax.set_ylim(-0.5, n_q - 0.5)
        ax.set_xlabel("e2e time (ms, log)")
        ax.grid(True, which="major", axis="x", ls=":", alpha=0.4)
        ax.set_axisbelow(True)
        fig.suptitle(
            f"{label} vs PostgreSQL — per-query e2e on JOB "
            f"({n_q} queries · geomean {label}/PG = {gm:.2f}× · "
            f"{label} faster on {wins}, slower on {losses})",
            y=0.995, fontsize=11,
        )
        ax.legend(fontsize=10, ncol=2,
                  loc="upper center", bbox_to_anchor=(0.5, 1.02),
                  frameon=True, facecolor="white", framealpha=0.95)
        plt.tight_layout(rect=[0, 0.005, 1, 0.97])
        if tag_override is not None:
            suffix = f"_{tag_override}"
        elif min_n > 0 and max_n is not None:
            suffix = f"_n{min_n}-{max_n}"
        elif min_n > 0:
            suffix = f"_nge{min_n}"
        elif max_n is not None:
            suffix = f"_nle{max_n}"
        else:
            suffix = ""
        out = out_dir / f"{key}_vs_pg_per_query{suffix}.png"
        fig.savefig(out, dpi=120, bbox_inches="tight")
        plt.close(fig)
        print(f"  -> {out}")
        continue

    # wrap into multiple rows if there are too many queries to fit one line
    n_rows = force_rows if force_rows else max(1, math.ceil(n_q / ROW_MAX))
    per_row = math.ceil(n_q / n_rows)
    fig_w = max(10, 0.50 * per_row)
    fig_h = 5.5 * n_rows + 0.5
    fig, axes = plt.subplots(n_rows, 1, figsize=(fig_w, fig_h),
                             squeeze=False)

    # share Y-range across rows
    ymin = max(0.5, min(min(pg_vals_all), min(me_vals_all)) * 0.7)
    ymax = max(max(pg_vals_all), max(me_vals_all)) * 1.4

    width = 0.4
    for row in range(n_rows):
        ax = axes[row, 0]
        lo, hi = row * per_row, min(n_q, (row + 1) * per_row)
        sub = data[lo:hi]
        x = np.arange(len(sub))
        pg_vals = [r["pg"] for r, _ in sub]
        me_vals = [v for _, v in sub]
        ax.bar(x - width / 2, pg_vals, width, color=PG[2],
               edgecolor="black", linewidth=0.2,
               label="PostgreSQL" if row == 0 else None)
        ax.bar(x + width / 2, me_vals, width, color=colour,
               edgecolor="black", linewidth=0.2,
               label=label if row == 0 else None)
        ax.set_yscale("log")
        ax.set_ylim(ymin, ymax)
        ax.set_xticks(x)
        ax.set_xticklabels([f"{r['q']}\n(n={r['n']})" for r, _ in sub],
                           rotation=70, ha="right", fontsize=7)
        ax.set_ylabel("e2e (ms, log)")
        ax.grid(True, which="major", axis="y", ls=":", alpha=0.4)
        ax.set_axisbelow(True)
        if n_rows > 1:
            ax.set_title(f"queries {lo + 1}-{hi}", fontsize=9, loc="left")

    fig.suptitle(
        f"{label} vs PostgreSQL — per-query e2e on JOB "
        f"({n_q} queries · geomean {label}/PG = {gm:.2f}× · "
        f"{label} faster on {wins}, slower on {losses})",
        y=0.995, fontsize=11,
    )
    axes[0, 0].legend(
        fontsize=10, ncol=2,
        loc="upper center", bbox_to_anchor=(0.5, 1.10 if n_rows == 1 else 1.18),
        frameon=True, facecolor="white", framealpha=0.95,
    )

    plt.tight_layout(rect=[0, 0.01, 1, 0.94 if n_rows == 1 else 0.97])
    if tag_override is not None:
        suffix = f"_{tag_override}"
    elif min_n > 0 and max_n is not None:
        suffix = f"_n{min_n}-{max_n}"
    elif min_n > 0:
        suffix = f"_nge{min_n}"
    elif max_n is not None:
        suffix = f"_nle{max_n}"
    else:
        suffix = ""
    out = out_dir / f"{key}_vs_pg_per_query{suffix}.png"
    fig.savefig(out, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"  -> {out}")
