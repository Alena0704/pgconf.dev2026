#!/usr/bin/env python3
"""All-methods per-query e2e comparison — one chart, bars per algorithm.

Reads plot_data/all_methods.csv (wide format: query, n_rel, <method>_e2e_ms…)
and writes plots/all_methods_per_query.png — one grouped-bar chart with one
bar per algorithm for every query, log Y-axis, style matching
saio_planning_vs_exec.png.

Methods plotted (in order): postgres, HyperQO, AlphaJoin, Bao, Neo, SkinnerDB,
MCTS.  Planning/exec stacking is only available for PG; other methods show
total e2e as a single bar.

Options:
    --src=PATH    override CSV path (default: plot_data/all_methods.csv)
    --min-n=N     only queries with n_rel >= N (default 0 = all)
    --out=PATH    output PNG (default plots/all_methods_per_query.png)
"""
import csv
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
src = HERE / "plot_data" / "all_methods.csv"
out = HERE / "plots" / "all_methods_per_query.png"
min_n = 0

for i, a in enumerate(sys.argv):
    if a.startswith("--src="):   src = Path(a.split("=", 1)[1])
    elif a == "--src" and i + 1 < len(sys.argv):
        src = Path(sys.argv[i + 1])
    elif a.startswith("--min-n="): min_n = int(a.split("=", 1)[1])
    elif a.startswith("--out="):   out = Path(a.split("=", 1)[1])

# (csv-key, display label, colour)
METHODS = [
    ("pg",      "PostgreSQL", "#1f4e79"),
    ("hq",      "HyperQO",    "#3a7c2f"),
    ("alpha",   "AlphaJoin",  "#7a4a1f"),
    ("bao",     "Bao",        "#a35e00"),
    ("neo",     "Neo",        "#6b4f9b"),
    ("skinner", "SkinnerDB",  "#1f6f7a"),
    ("mcts",    "MCTS",       "#c14c2f"),
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
        for key, _, _ in METHODS:
            v = r.get(f"{key}_e2e_ms", "")
            try:
                fv = float(v)
                rec[key] = fv if fv > 0 else None
            except ValueError:
                rec[key] = None
        rows.append(rec)

rows = [r for r in rows if r["n"] >= min_n]
if not rows:
    print("no rows after filtering", file=sys.stderr)
    sys.exit(1)

# Sort: by n_rel asc, then by PG e2e asc (queries with no PG go to end)
rows.sort(key=lambda r: (r["n"], r.get("pg") or float("inf")))

n_queries = len(rows)
n_methods = len(METHODS)
print(f"queries: {n_queries}   methods: {n_methods}   min_n={min_n}")

# Figure width scales with number of queries so labels stay legible.
fig_w = max(14, 0.55 * n_queries)
fig_h = 7.5
fig, ax = plt.subplots(figsize=(fig_w, fig_h))

width = 0.85 / n_methods
x = np.arange(n_queries)

for i, (key, label, colour) in enumerate(METHODS):
    offset = (i - (n_methods - 1) / 2.0) * width
    vals = [r.get(key) or 0 for r in rows]
    ax.bar(x + offset, vals, width, color=colour, label=label,
           edgecolor="black", linewidth=0.15)

ax.set_yscale("log")
ax.set_xticks(x)
ax.set_xticklabels([f"{r['q']}\n(n={r['n']})" for r in rows],
                   rotation=70, ha="right", fontsize=7)
ax.set_ylabel("e2e time (ms, log)")
fig.suptitle(
    "JOB per-query e2e — PostgreSQL vs learned/MCTS optimizers  "
    f"({n_queries} queries)",
    y=0.995, fontsize=12,
)
ax.legend(fontsize=9, ncol=len(METHODS),
          loc="upper center", bbox_to_anchor=(0.5, 1.06),
          frameon=True, facecolor="white", framealpha=0.95)
ax.grid(True, which="major", axis="y", ls=":", alpha=0.4)
ax.set_axisbelow(True)

# Marker for PG baseline as a thin horizontal stripe — visually anchors the eye.
ax.axhline(1.0, color="black", lw=0.5, alpha=0.3)

fig.text(0.5, -0.01,
         "Bars are per-query median e2e (planning + execution).  Lower is faster.",
         ha="center", fontsize=9, style="italic", color="#444")
plt.tight_layout(rect=[0, 0.01, 1, 0.92])
out.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(out, dpi=120, bbox_inches="tight")
plt.close(fig)
print(f"  -> {out}")
