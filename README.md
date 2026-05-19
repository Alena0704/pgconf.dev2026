# min_job — JOB benchmark runner for PostgreSQL and learned optimizers

A minimal set of bash scripts to run the [Join Order Benchmark (JOB)](https://github.com/gregrahn/join-order-benchmark) against:

- vanilla PostgreSQL (current `my_postgres10` build);
- **Bao** (learned planner-hook on a separate PG fork);
- **Neo** (neural optimizer, hints via `pg_hint_plan`);
- **Balsa** (successor to Neo by the same authors);
- **HyperQO** / **AlphaJoin** (hint-based learned optimizers — replayed from prior measurements in `plot_data/all_methods.csv`);
- **SkinnerDB** (standalone Java DBMS, no PostgreSQL);
- **MCTS-Extreme** (this repo's `contrib/mcts_extreme`);
- **AQO** (this repo's `contrib/aqo` — adaptive cardinality learning);
- **SAIO** (ported PGXN extension `contrib/saio` — simulated-annealing join-order search; see [SAIO_REPORT.md](SAIO_REPORT.md) for the port story and bug fixes).

Each base runner does the same three things:
1. Reads queries from `$QUERY_FILES` (default [source/queries/](source/queries/)).
2. Saves the `EXPLAIN` plan to `plans/<method>/<query>.plan`.
3. Runs each query `ITERS` times and writes timings to `results/<method>_job.csv`.

After a run, [collect.sh](collect.sh) aggregates all `results/*_job.csv` into a single wide table `results/job_aggregate.csv` (median / p95 / min / max / n per query and method).

---

## Directory layout

| File / dir | Purpose |
|---|---|
| [lib.sh](lib.sh) | Shared variables (`PG_BASE`, `INSTDIR`, `PGDATA`, `PGPORT`, `QUERY_DIR`, `ITERS`, …) and helpers (`pg_ensure_up`, `run_query_once`, `save_plain_explain`, `csv_header`). Every other script does `source ./lib.sh`. |
| [job_create.sh](job_create.sh) | Creates the `imdb` DB, applies `schema.sql`, loads CSVs via `copy.sql`, creates FK indexes, runs `VACUUM ANALYZE`. |
| [job_run.sh](job_run.sh) | Runs against vanilla PG (method `plain_pg`). |
| [job_run_bao.sh](job_run_bao.sh) | Runs through Bao (port 5500, separate PG build, requires `bao_server` running). |
| [job_run_neo.sh](job_run_neo.sh) | Runs through Neo (port 5501, requires `pg_hint_plan` and pre-generated hints). |
| [job_run_balsa.sh](job_run_balsa.sh) | Runs through Balsa (port 5502, requires `pg_hint_plan` and hints). |
| [job_run_skinner.sh](job_run_skinner.sh) | Runs through SkinnerDB (Java jar, no PG). |
| [bao_train_and_test.sh](bao_train_and_test.sh) | Online-train Bao on JOB (`EPOCHS` passes, retrains every 25 queries), then one clean test pass into `results/bao_job.csv`. |
| [job_run_mcts_approbation.sh](job_run_mcts_approbation.sh) | Approbation sweep for MCTS along the `reward_mode × luby × rollout` axes, on the production-best substrate. |
| [job_run_mcts_ablation.sh](job_run_mcts_ablation.sh) | **Ablation**: start from production-best, turn ONE feature off at a time, measure the cost of removing each (gate, top_k, depth, kernels, luby, …). |
| [job_run_mcts_aqo.sh](job_run_mcts_aqo.sh) | Three-way: `plain_pg` / `mcts_only` / `mcts_aqo`. Measures how much per-query cardinality correction (AQO `learn`) helps MCTS converge across the 5 reruns. |
| [job_compare_methods.sh](job_compare_methods.sh) | Head-to-head comparison: `pg / mcts / pg_aqo / mcts_aqo` over JOB; AQO in `controlled` mode for stable cardinality estimates. |
| [job_cardinality_analysis.sh](job_cardinality_analysis.sh) | Per-node q-error analysis via `EXPLAIN (ANALYZE, VERBOSE, BUFFERS)` for the same configs. Phase B of the cardinality study. |
| [job_dump_plans.sh](job_dump_plans.sh) | Standalone `EXPLAIN` dumper — saves plans per `(config, query)` and a side-by-side digest. |
| [job_greedy_mcts.sh](job_greedy_mcts.sh) | Coordinate-descent (greedy) tuner over MCTS GUCs. Supports env-var pinning for multi-pass runs. |
| [job_run_saio_vs_pg.sh](job_run_saio_vs_pg.sh) | `pg` vs `saio` (defaults) on JOB queries with `n_rels > 11` (GEQO threshold). Captures `planning_ms` and `exec_ms` separately. |
| [job_run_saio_configs.sh](job_run_saio_configs.sh) | Multi-config SAIO sweep — `pg` plus `saio_default / saio_mid / saio_cheap / saio_cheap_r3 / saio_cheap_r5` over JOB. Drives the SAIO findings in [SAIO_REPORT.md](SAIO_REPORT.md). |
| [job_saio_tuning_pilot.sh](job_saio_tuning_pilot.sh) | SAIO parameter pilot on 4 worst-case JOB queries — exploratory sweep before launching the full multi-config run. Writes to `results/saio_tuning/<run-id>/`. |
| [aqo_setup.sh](aqo_setup.sh) | Builds & installs AQO, adds it to `shared_preload_libraries`, raises hash-table limits (`fs_max_items`, `fss_max_items`, `dsm_size_max`), restarts PG, runs `CREATE EXTENSION aqo`. |
| [aqo_train.sh](aqo_train.sh) | Trains AQO over N iterations on the JOB workload, with optional `--with-mcts` to train on MCTS-shaped plans, `--no-reset` to keep prior state. Tracks per-iter geomean exec time, learned-query count, and AQO q-error from `aqo_query_stat`. |
| [collect.sh](collect.sh) | Folds `results/*_job.csv` into `results/job_aggregate.csv`. |
| [source/](source/) | Fork of [join-order-benchmark](https://github.com/gregrahn/join-order-benchmark): `schema.sql`, `copy.sql`, `fkindexes.sql`, IMDb CSV data (`source/csv/`), 113 queries (`source/queries/`). |
| [articles/](articles/) | Reading list (PDFs) organised by topic: `base/` (Selinger, Monma-Sidney, DPhyp, JOB), `AI/` (Neo, Bao, Balsa, DQ, DeepDB, RTOS, HyperQO, JOGGER, LLMSteer, surveys), `MCTS/` (AlphaJoin, HyperQO, our practical-MCTS draft), `randomised/` (Ioannidis-Kang, quantum ant-colony, LOAM), `reopt/` (SkinnerDB, QuerySplit, Liu-Ives, Robust JO), `extra/`. |
| [plot_data/](plot_data/) | Pre-aggregated CSVs that feed the cross-method plot scripts: `all_methods.csv` (wide format: `query,n_rel,pg_e2e_ms,hq_e2e_ms,alpha_e2e_ms,mcts_e2e_ms,bao_e2e_ms,neo_e2e_ms,skinner_e2e_ms`), `e2e_by_size.csv`. |
| `plans/<method>/` | (created on run) plain-text `EXPLAIN` plans. |
| `results/<method>_job.csv` | (created on run) `query,iter,exec_ms`. |
| `results/compare/<run-id>/` | (created on run) MCTS-vs-AQO compare-run output: `per_query.csv`, `summary.csv`, `plans/<cfg>/`. |
| `results/compare_saio/<run-id>/` | (created on run) SAIO compare runs: `per_query.csv` with `planning_ms,exec_ms`, `summary.csv`. |
| `results/saio_tuning/<run-id>/` | (created on run) SAIO tuning pilots. |
| `logs/` | (created on run) cluster logs. |
| [SAIO_REPORT.md](SAIO_REPORT.md) | Port of PGXN saio to PG 19devel: API migration, two runtime bugs (`get_all_nodes_rec` losing nodes; `saio_move` early-exit), `saio_restarts` GUC, and the empirical SAIO-vs-PG comparison on all 113 JOB queries. |
| [RESULTS.md](RESULTS.md) | Aggregated results / talk-track for the JOB head-to-head numbers. |

### Analysis & plot scripts

All plot scripts write into [plots/](plots/) and accept an optional `--src=PATH` to point at an explicit CSV instead of the latest auto-detected run.

| Script | Inputs | Outputs |
|---|---|---|
| [make_compare_plots.py](make_compare_plots.py) | `$BENCH_ROOT/results/compare/<latest>/per_query.csv` | `slide37_worst_best_ratio.png`, `e2e_scatter_all.png`, `e2e_per_query_ratio_sorted.png`. |
| [make_e2e_scatter_split.py](make_e2e_scatter_split.py) | `plot_data/all_methods.csv` | One log-log scatter per method vs PG (`e2e_scatter_{hq,alpha,bao,neo,skinner,mcts}.png`) — same data as the 2×3 `e2e_scatter_all.png` grid. |
| [make_method_vs_pg_per_query.py](make_method_vs_pg_per_query.py) | `plot_data/all_methods.csv` | Per-algorithm grouped bar charts (PG vs method, one bar per query). Flags: `--min-n=N` / `--max-n=N` to restrict by `n_rel`, `--tag=STR` to suffix the filename (e.g. `_small` / `_large`), `--rows=N` to force vertical wrap into N subplot rows, `--horizontal` for tall barh layout. |
| [make_all_methods_per_query.py](make_all_methods_per_query.py) | `plot_data/all_methods.csv` | Single grouped bar chart with all 7 methods (`PG · HyperQO · AlphaJoin · Bao · Neo · SkinnerDB · MCTS`) per query, log Y. Flags: `--min-n=N`, `--out=PATH`. |
| [make_saio_plots.py](make_saio_plots.py) | `$BENCH_ROOT/results/compare_saio/<latest>/per_query.csv` (pg + saio) | `saio_e2e_scatter.png` (planning / execution / total scatter), `saio_e2e_ratio_sorted.png`, `saio_planning_vs_exec.png` (stacked side-by-side bars). |
| [make_saio_configs_plots.py](make_saio_configs_plots.py) | `$BENCH_ROOT/results/compare_saio/<latest>/per_query.csv` (pg + N saio variants) | `saio_configs_e2e_scatter.png`, `saio_configs_e2e_ratio.png`, `saio_configs_by_nrels.png`, `saio_configs_planning_vs_exec.png`. |
| [make_per_query_planning_exec.py](make_per_query_planning_exec.py) | `$BENCH_ROOT/results/compare_saio/<latest>/per_query.csv` | One stacked-bar PNG per query in [plots/per_query/](plots/per_query/) — every non-pg config side-by-side with PG. Flags: `--min-n=N` (default 12), `--queries=10a,11b,...`. |
| [analyze_compare.py](analyze_compare.py) | `$BENCH_ROOT/results/compare/<latest>/per_query.csv` | Numeric breakdown of AQO's effect on PG vs MCTS (`pg_aqo/pg` vs `mcts_aqo/mcts`); writes `plots/aqo_improvement.png` plus updates the slide37 / scatter PNGs. |

---

## Environment variables (from [lib.sh](lib.sh))

Override with `export` before invoking the script.

| Variable | Default | Meaning |
|---|---|---|
| `PG_BASE` | `$HOME/my_postgres10` | Single point of customization. All other PG paths derive from this. |
| `PG_DATA_NAME` | `vacuum_stats9` | Subdir name under `$PG_BASE` for `PGDATA`. |
| `INSTDIR` | `$PG_BASE/my/inst/bin` | PG bin directory. |
| `PGDATA` | `$PG_BASE/$PG_DATA_NAME` | Cluster data dir. |
| `PGPORT` | `5499` | Vanilla PG port. |
| `PGUSER` | `$(whoami)` | |
| `PGDATABASE` | `postgres` | Used before `imdb` is created. |
| `QUERY_DIR` | `$HOME/source` | Root of the JOB fork (`schema.sql`, `csv/`, `queries/` live here). |
| `QUERY_FILES` | `$QUERY_DIR/queries` | Directory with `*.sql`. |
| `BENCH_ROOT` | `$HOME/min_job` | Where to write `plans/`, `results/`, `logs/`. |
| `ITERS` | `5` | Reruns per query. |
| `STATEMENT_TIMEOUT_MS` | `600000` | 10 minutes per query. |

Each learned optimizer brings its own `*_PORT`, `*_PGDATA`, `*_INSTDIR`, `*_HINTS_DIR` — see the header of the matching `job_run_*.sh`.

---

## End-to-end run

```bash
# 0. Bring up the cluster and confirm it listens on 5499
#    (lib.sh::pg_ensure_up does this automatically).

# 1. Create the imdb DB from CSVs (source — source/)
export QUERY_DIR=$HOME/min_job/source
./job_create.sh imdb

# 2. Baseline run against vanilla PG
./job_run.sh imdb 5      # 5 iters per query -> results/plain_pg_job.csv

# 3. (Optional) AQO setup + training
./aqo_setup.sh imdb              # extension + raised hash limits + restart
./aqo_train.sh imdb 30           # 30 iters; AQO learns from DP/GEQO plans
./aqo_train.sh imdb 30 \         # additional pass: AQO also learns
              --with-mcts \      #   from MCTS-shaped plans
              --no-reset         #   preserves prior learning

# 4. Each learned optimizer (see prerequisites below)
./job_run_bao.sh     imdb 5
./job_run_neo.sh     imdb 5
./job_run_balsa.sh   imdb 5
./job_run_skinner.sh        5

# 5. Head-to-head: pg vs mcts, with and without AQO (4 configs × 113 queries × ITERS)
./job_compare_methods.sh imdb 5

# 6. SAIO comparisons (optional)
./job_run_saio_vs_pg.sh    imdb 3 12  # 2-way: pg vs saio on n_rels>=12
./job_run_saio_configs.sh  imdb 3 12  # multi-config sweep

# 7. Build plots from the latest runs
python3 make_compare_plots.py             # pg/mcts/aqo comparisons
python3 make_saio_plots.py                # saio 2-way
python3 make_saio_configs_plots.py        # saio multi-config
python3 make_per_query_planning_exec.py   # per-query stacked bars
python3 make_all_methods_per_query.py     # all 7 optimizers, one chart
python3 make_method_vs_pg_per_query.py --max-n=11 --tag=small --rows=2
python3 make_method_vs_pg_per_query.py --min-n=12 --tag=large

# 8. Aggregate everything
./collect.sh             # -> results/job_aggregate.csv
```

---

## MCTS-Extreme + AQO workflow

This repo's `contrib/mcts_extreme` adds an MCTS-based join-search planner; `contrib/aqo` learns cardinality predictions from past executions. They compose: MCTS provides the join order, AQO provides the row estimates that drive cost-based pruning inside MCTS.

The typical pipeline:

```bash
# A. Build & install AQO; raise hash-table limits in postgresql.conf;
#    restart PG; CREATE EXTENSION aqo.
./aqo_setup.sh imdb

# B. Train AQO over N iters (mode='learn' by default).
./aqo_train.sh imdb 30                      # AQO learns from PG-DP/GEQO plans
./aqo_train.sh imdb 30 --with-mcts --no-reset  # AQO also learns from MCTS plans
# Outputs: results/aqo_train/<run-id>/{summary.csv,per_query.csv,log.txt}

# C. Compare planning methods at AQO-converged cardinalities.
./job_compare_methods.sh imdb 5
# Six possible configs (default: 4):
#   pg          PG default join search.  No AQO.
#   mcts        MCTS-extreme on ALL queries.  No AQO.
#   pg_aqo      PG + AQO controlled (uses learned cardinalities).
#   mcts_aqo    MCTS + AQO.   ★ flagship.
#   dp_only     diagnostic: force DP for all n_rels.
#   geqo_only   diagnostic: force GEQO for all n_rels.

# D. Per-node cardinality q-error analysis on the same configs.
./job_cardinality_analysis.sh imdb 1   # uses EXPLAIN (ANALYZE, VERBOSE)

# E. Ablation: cost of removing each MCTS feature from production-best.
./job_run_mcts_ablation.sh imdb 5
# Variants: pg, best, no_gate, k0_bushy, k_heur, k_bandit, with_topk5,
#           low_depth, low_budget, no_luby, reward_avg

# F. Plots.
python3 make_compare_plots.py
```

`job_compare_methods.sh` saves per-query plans alongside its CSV — output layout:

```
$RESULTS_DIR/compare/<run-id>/
├── per_query.csv      (query,n_rels,config,iter,exec_ms,top_cost)
├── summary.csv        (per-config geomean / median / wins-vs-pg / losses-vs-pg / geo_ratio_vs_pg)
├── log.txt
└── plans/
    ├── pg/<query>.plan
    ├── mcts/<query>.plan
    ├── pg_aqo/<query>.plan
    └── mcts_aqo/<query>.plan
```

For visual per-query comparison, use `job_dump_plans.sh` to produce a side-by-side digest:

```bash
./job_dump_plans.sh imdb 0   # 0 = plain EXPLAIN (fast).  1 = EXPLAIN ANALYZE (slow).
# -> $PLANS_DIR/<config>/<query>.plan
# -> $PLANS_DIR/diff/<query>.txt   -- aligned blocks of all configs
```

---

## SAIO workflow

`contrib/saio` is this repo's port of the PGXN `saio` extension (J. Urbański's simulated-annealing join planner) onto PG 19devel. The port fixes two long-standing runtime bugs and adds multi-restart via the new `saio_restarts` GUC — see [SAIO_REPORT.md](SAIO_REPORT.md) for the full story.

The driver scripts all share output schema `query,n_rels,config,iter,planning_ms,exec_ms,top_cost`, so all SAIO plot scripts work on any of their outputs.

```bash
# A. Build SAIO and ensure it's on the dynamic-library path.
cd ../contrib/saio && make && make install

# B. Quick pilot: SAIO defaults vs custom tunings on the 4 worst-case queries.
./job_saio_tuning_pilot.sh imdb 3
# -> $RESULTS_DIR/saio_tuning/<run-id>/per_query.csv

# C. Head-to-head: pg vs saio (defaults) on all queries with n_rels > 11.
./job_run_saio_vs_pg.sh imdb 3 12
# -> $RESULTS_DIR/compare_saio/<run-id>/per_query.csv

# D. Multi-config sweep: pg + saio_default + saio_cheap + saio_cheap_r3 …
./job_run_saio_configs.sh imdb 3 12

# E. Plots from any of the above runs.
python3 make_saio_plots.py             # 2-config run (pg + saio)
python3 make_saio_configs_plots.py     # N-config sweep
python3 make_per_query_planning_exec.py        # one PNG per query
python3 make_per_query_planning_exec.py --min-n=0   # … including small queries
```

`make_per_query_planning_exec.py` auto-detects every non-pg config in the run and stacks them side-by-side per query, so the same plot script works for a 2-way `pg vs saio` comparison and for the full `pg / saio_default / saio_cheap / saio_cheap_r3` matrix.

The headline SAIO result on JOB (113 queries, `saio_cheap` config): SAIO wins outright on 10 queries (9%), loses within 2× on 51%, loses 2–5× on 29%; the most dramatic single-query speedup is **31c (n_rels=11)** — PG 20.3 s → SAIO 0.9 s — and 31c is a DP query, not a GEQO one. Full breakdown in [SAIO_REPORT.md](SAIO_REPORT.md).

---

## Cross-method comparison (all 7 optimizers)

`plot_data/all_methods.csv` is the canonical wide-format CSV behind every cross-method chart. It pre-aggregates per-query medians for `pg / hq / alpha / bao / neo / skinner / mcts` so the plotting scripts don't need to re-run any optimizer:

```bash
# Single combined chart, all queries.
python3 make_all_methods_per_query.py

# Same chart, restricted to n_rel >= 12 (the GEQO-trigger subset).
python3 make_all_methods_per_query.py --min-n=12 --out=plots/all_methods_per_query_n12.png

# One PG-vs-method bar chart per algorithm, split into "small" (n<12) and "large" (n>=12).
python3 make_method_vs_pg_per_query.py --max-n=11 --tag=small --rows=2
python3 make_method_vs_pg_per_query.py --min-n=12 --tag=large

# One log-log scatter per method (vs PG) — same data as the e2e_scatter_all.png grid.
python3 make_e2e_scatter_split.py
```

`--rows=N` for vertical bar charts wraps a long query list into N stacked subplot rows (useful when the small subset is 93 queries wide); `--horizontal` flips to one row per query.

---

## Where to get the external repositories

All learned optimizers below are external projects — **not vendored here**. The `job_run_*.sh` scripts assume you cloned them into `$HOME` and built them. CPU-only PyTorch is sufficient for the ML methods (no CUDA needed); training on CPU takes hours.

> **Adapted forks at [github.com/Alena0704](https://github.com/Alena0704)** — every repo referenced below has a fork on my GitHub patched to build against the current PostgreSQL master (PG 19devel) used in this repo. Upstream branches in many of these projects target PG 11–14 and no longer compile cleanly against master (API drift in `pathnodes.h`, list-as-array changes, `pg_prng_*`, extension-state API, …). Prefer cloning my forks when you reproduce the JOB pipeline here; the upstream repos are still listed for traceability.
>
> **Pinned upstream PG commit.** All forks here are built and tested against PostgreSQL master at:
>
> > `a0a0c0c20ec5f8787bb1be5f476c4e59f6810634` — *"Skip other sessions' temp tables in REPACK, CLUSTER, and VACUUM FULL"* (Álvaro Herrera, 2026-05-05)
>
> This is the commit that `origin/HEAD` of the PG mirror in this repo points to. If you build against a substantially newer master, expect minor `pathnodes.h` / planner-API drift; the patch series in each fork tracks this commit and may need a small rebase forward.
>
> Direct fork links:
> [saio](https://github.com/Alena0704/saio) · [aqo](https://github.com/Alena0704/aqo) · [Neo](https://github.com/Alena0704/Neo) · [balsa](https://github.com/Alena0704/balsa) · [BaoForPostgreSQL](https://github.com/Alena0704/BaoForPostgreSQL) · [skinnerdb](https://github.com/Alena0704/skinnerdb) · [jo-bench](https://github.com/Alena0704/jo-bench) · [parameterized-jo-bench](https://github.com/Alena0704/parameterized-jo-bench) · [pg_track_optimizer](https://github.com/Alena0704/pg_track_optimizer) · [postgres](https://github.com/Alena0704/postgres) (PG master mirror with my patches).

### Bao — upstream [learnedsystems/BaoForPostgreSQL](https://github.com/learnedsystems/BaoForPostgreSQL) · fork [Alena0704/BaoForPostgreSQL](https://github.com/Alena0704/BaoForPostgreSQL) (adapted to current master)

```bash
git clone https://github.com/Alena0704/BaoForPostgreSQL ~/BaoForPostgreSQL
cd ~/BaoForPostgreSQL/pg_extension && make USE_PGXS=1 install
initdb -D ~/bao_pgdata
pg_ctl -D ~/bao_pgdata -o "-p 5500" start
psql -p 5500 postgres -c "CREATE EXTENSION pg_bao"
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r ~/BaoForPostgreSQL/bao_server/requirements.txt
export CUDA_VISIBLE_DEVICES=""
cd ~/BaoForPostgreSQL/bao_server && python main.py   # listens on :9381
```

Then re-run `job_create.sh` against port 5500 to load IMDb into the Bao cluster. Bao ships its own PG fork (planner modifications), so `pg_bao` cannot be loaded into a vanilla PG. Marcus et al., SIGMOD 2021.

[job_run_bao.sh](job_run_bao.sh) checks that `bao_server` is listening on `http://localhost:9381`; otherwise `pg_bao` silently falls back to the default planner, and timings would reflect PG rather than Bao.

### Neo — upstream [KostasMparmparousis/Neo](https://github.com/KostasMparmparousis/Neo) · fork [Alena0704/Neo](https://github.com/Alena0704/Neo) (adapted to current master)

The original Marcus et al. (VLDB 2019) code was never released, so we use a community re-implementation. From 2022 onwards Neo has effectively been superseded by Balsa — if you pick one, pick Balsa.

```bash
git clone https://github.com/Alena0704/Neo ~/neo
# Build PG14 with pg_hint_plan:
git clone https://github.com/ossc-db/pg_hint_plan ~/pg_hint_plan
cd ~/pg_hint_plan && make PG_CONFIG=~/neo_pg/inst/bin/pg_config install
initdb -D ~/neo_pgdata
pg_ctl -D ~/neo_pgdata -o "-p 5501" start
echo "shared_preload_libraries = 'pg_hint_plan'" >> ~/neo_pgdata/postgresql.conf
pg_ctl -D ~/neo_pgdata restart
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r ~/neo/requirements.txt
export CUDA_VISIBLE_DEVICES=""
# Train Neo on the JOB train-split, then generate hints:
#   ~/neo/hints/<query>.hint   <- pg_hint_plan string per query
```

[job_run_neo.sh](job_run_neo.sh) reads the hint from `$NEO_HINTS_DIR/<query>.hint`, loads `pg_hint_plan`, prepends the hint to the SQL, and measures.

### Balsa — upstream [balsa-project/balsa](https://github.com/balsa-project/balsa) · fork [Alena0704/balsa](https://github.com/Alena0704/balsa) (adapted to current master)

Yang et al., SIGMOD 2022. Successor to Neo, trains without expert demonstrations.

```bash
git clone https://github.com/Alena0704/balsa ~/balsa
cd ~/balsa
./scripts/build_pg.sh    # builds PG14 with pg_hint_plan and Balsa's patch -> ~/balsa/inst/
./scripts/init_db.sh     # cluster on port 5502
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r ~/balsa/requirements.txt
export CUDA_VISIBLE_DEVICES=""
python -m balsa.train --workload=job --device=cpu
# Balsa writes per-query hints into ~/balsa/hints/job/<query>.hint
```

[job_run_balsa.sh](job_run_balsa.sh) applies the hint and times via `pg_hint_plan`, exactly like Neo.

### SkinnerDB — upstream [cornelldbgroup/skinnerdb](https://github.com/cornelldbgroup/skinnerdb) · fork [Alena0704/skinnerdb](https://github.com/Alena0704/skinnerdb) (adapted to current master)

Trummer et al., SIGMOD 2019. Standalone Java DBMS — **no PostgreSQL involved**.

```bash
git clone https://github.com/Alena0704/skinnerdb ~/SkinnerDB
cd ~/SkinnerDB && mvn package
# Load IMDb into SkinnerDB's bundled storage:
java -jar target/skinnerdb-1.0-SNAPSHOT-jar-with-dependencies.jar \
     --load $HOME/min_job/source/csv
```

[job_run_skinner.sh](job_run_skinner.sh) pipes SQL into the jar via stdin and parses the `Query took XXX ms` line. Neither `\timing` nor `pg_hint_plan` apply here.

### AQO — current-master builds

The upstream `postgrespro/aqo` `master` branch targets older PG releases. Two sources work against current master:

- [postgrespro/aqo@master_development](https://github.com/postgrespro/aqo/tree/master_development) — upstream development branch, follows the core-side patch that adds the AQO hooks.
- [Alena0704/postgres@aqo-patched-master](https://github.com/Alena0704/postgres/tree/aqo-patched-master) — full PG-master fork with the AQO core-hooks patch (`contrib/aqo/aqo_master.patch`) already applied; this is the branch the scripts here are tested against.

```bash
# Option A: build the PG fork that already has the AQO core hooks applied.
git clone -b aqo-patched-master https://github.com/Alena0704/postgres ~/my_postgres
cd ~/my_postgres && ./configure --prefix=$PWD/my/inst && make -j && make install
# AQO is in contrib/aqo/ on this branch; build & install it like any contrib module.
cd contrib/aqo && make && make install

# Option B: keep upstream PG and apply the dev-branch AQO on top.
git clone -b master_development https://github.com/postgrespro/aqo ~/aqo
# … then apply the matching core-hooks patch and rebuild PG (see aqo_setup.sh).
./aqo_setup.sh imdb
```

### SAIO — port to PG 19devel

[Alena0704/saio](https://github.com/Alena0704/saio) is the fork of [parkag/saio](https://github.com/parkag/saio) adapted to current master. The port story (API migration, two runtime bug fixes, new `saio_restarts` GUC) is documented in [SAIO_REPORT.md](SAIO_REPORT.md). The actual extension code lives in this repo at `contrib/saio/`.

---

## Notes

- The baseline `job_run_*.sh` scripts write CSVs in the same `query,iter,exec_ms` format, so [collect.sh](collect.sh) picks up any new method automatically — just drop a file into `results/<method>_job.csv`. The SAIO and AQO comparison scripts use the wider schema `query,n_rels,config,iter,planning_ms,exec_ms,top_cost` (one row per config) and write under `results/compare/<run-id>/` or `results/compare_saio/<run-id>/`.
- Bao is timed as plain wallclock (`\timing`) — that's total cost (planning + execution); Bao injects hints via `planner_hook`. Neo and Balsa are timed against pre-generated hints, so inference time is not part of `exec_ms`. HyperQO and AlphaJoin numbers in `plot_data/all_methods.csv` come from prior measurements and include their own planning overhead.
- The IMDb deployment has only been tested in C-locale (see [source/README.md](source/README.md)).
- AQO requires the core hooks patch from [contrib/aqo/aqo_master.patch](../contrib/aqo/aqo_master.patch) — without it, `CREATE EXTENSION aqo` will segfault on `pg_extension` lookups. The patch is committed on this branch (`add-adaptive-kernel`); rebuild PG after applying it.
- MCTS-Extreme's production-best config (`fixed K=1, min_relations=13, depth=8, top_k=0, expl=1.0, budget=100, phases=5`) is documented in `min_job/adaptive_kernels/PARAM_STUDY.md`. The comparison and ablation scripts use `min_relations=2` so MCTS runs on every query — for a head-to-head with DP/GEQO across the full workload.
- SAIO's "cheap" tuning (`saio_equilibrium_factor=4, saio_temperature_reduction_factor=0.7, saio_moves_before_frozen=2`) brings planning overhead down from 5–11 s (defaults) to 0.3–0.8 s; the `_r3` / `_r5` variants enable multi-restart (`saio_restarts=3` / `5`) to recover from local minima. See [SAIO_REPORT.md §3](SAIO_REPORT.md) for the ablation.
- `plot_data/all_methods.csv` is a pre-aggregated wide-format snapshot — regenerating it requires re-running the relevant `job_run_*.sh` and folding the outputs together; the cross-method plot scripts read this CSV directly and don't re-execute any queries.
