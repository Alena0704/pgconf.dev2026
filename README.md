# min_job — JOB benchmark runner for PostgreSQL and learned optimizers

Минимальный набор bash-скриптов для прогона [Join Order Benchmark (JOB)](https://github.com/gregrahn/join-order-benchmark) на:

- ванильном PostgreSQL (текущая сборка `my_postgres9`);
- **Bao** (learned planner-hook на отдельном форке PG);
- **Neo** (нейронный оптимизатор, hints через `pg_hint_plan`);
- **Balsa** (преемник Neo от тех же авторов);
- **SkinnerDB** (standalone Java DBMS, без PostgreSQL).

Каждый скрипт делает одно и то же:
1. Берёт запросы из `$QUERY_FILES` (по умолчанию [source/queries/](source/queries/)).
2. Сохраняет `EXPLAIN` план в `plans/<method>/<query>.plan`.
3. Гоняет запрос `ITERS` раз и пишет тайминги в `results/<method>_job.csv`.

После прогона [collect.sh](collect.sh) собирает все `results/*_job.csv` в одну широкую таблицу `results/job_aggregate.csv` (median / p95 / min / max / n по каждому запросу и методу).

---

## Структура директории

| Файл / директория | Назначение |
|---|---|
| [lib.sh](lib.sh) | Общие переменные (`INSTDIR`, `PGDATA`, `PGPORT`, `QUERY_DIR`, `ITERS`, …) и хелперы (`pg_ensure_up`, `run_query_once`, `save_plain_explain`, `csv_header`). Все остальные скрипты делают `source ./lib.sh`. |
| [job_create.sh](job_create.sh) | Создаёт БД `imdb`, накатывает `schema.sql`, заливает CSV через `copy.sql`, создаёт FK-индексы, `VACUUM ANALYZE`. |
| [job_run.sh](job_run.sh) | Прогон на ванильном PG (метод `plain_pg`). |
| [job_run_bao.sh](job_run_bao.sh) | Прогон через Bao (порт 5500, своя сборка PG, нужен запущенный `bao_server`). |
| [job_run_neo.sh](job_run_neo.sh) | Прогон через Neo (порт 5501, нужен `pg_hint_plan` и предсгенерённые хинты). |
| [job_run_balsa.sh](job_run_balsa.sh) | Прогон через Balsa (порт 5502, нужен `pg_hint_plan` и хинты). |
| [job_run_skinner.sh](job_run_skinner.sh) | Прогон через SkinnerDB (Java jar, без PG). |
| [collect.sh](collect.sh) | Сводит `results/*_job.csv` в `results/job_aggregate.csv`. |
| [source/](source/) | Форк [join-order-benchmark](https://github.com/gregrahn/join-order-benchmark): `schema.sql`, `copy.sql`, `fkindexes.sql`, CSV-данные IMDb (`source/csv/`), 113 запросов (`source/queries/`). |
| `plans/<method>/` | (создаётся при прогоне) текстовые планы `EXPLAIN`. |
| `results/<method>_job.csv` | (создаётся при прогоне) `query,iter,exec_ms`. |
| `logs/` | (создаётся при прогоне) логи кластера. |

---

## Переменные окружения (из [lib.sh](lib.sh))

Перекрываются через `export` перед запуском скрипта.

| Переменная | Значение по умолчанию | Что значит |
|---|---|---|
| `INSTDIR` | `/home/alena/my_postgres9/my/inst/bin` | bin-директория сборки PG. |
| `PGDATA` | `/home/alena/my_postgres9/vacuum_stats9` | кластер. |
| `PGPORT` | `5499` | порт ванильного PG. |
| `PGUSER` | `$(whoami)` | |
| `PGDATABASE` | `postgres` | используется до создания `imdb`. |
| `QUERY_DIR` | `/home/alena/source` | корень JOB-форка (там лежит `schema.sql`, `csv/`, `queries/`). |
| `QUERY_FILES` | `$QUERY_DIR/queries` | директория с `*.sql`. |
| `BENCH_ROOT` | `/home/alena/min_job` | куда писать `plans/`, `results/`, `logs/`. |
| `ITERS` | `5` | сколько раз гонять каждый запрос. |
| `STATEMENT_TIMEOUT_MS` | `600000` | 10 минут на запрос. |

Для каждого learned-оптимизатора есть свои `*_PORT`, `*_PGDATA`, `*_INSTDIR`, `*_HINTS_DIR` — смотри заголовок соответствующего `job_run_*.sh`.

---

## Полный сценарий запуска

```bash
# 0. Поднять кластер my_postgres9 и убедиться что он слушает на 5499
#    (lib.sh::pg_ensure_up делает это автоматически).

# 1. Создать БД imdb из CSV (источник — source/)
export QUERY_DIR=/home/alena/min_job/source
./job_create.sh imdb

# 2. Базовый прогон на ванильном PG
./job_run.sh imdb 5      # 5 итераций на запрос -> results/plain_pg_job.csv

# 3. Прогон через каждый learned-оптимизатор (см. подготовку ниже)
./job_run_bao.sh     imdb 5
./job_run_neo.sh     imdb 5
./job_run_balsa.sh   imdb 5
./job_run_skinner.sh        5

# 4. Сводная таблица
./collect.sh             # -> results/job_aggregate.csv
```

---

## Откуда брать внешние репозитории

Все четыре оптимизатора — внешние проекты, в этом репо их **нет**. Скрипты `job_run_*.sh` рассчитывают, что вы клонировали их в `$HOME` и собрали. CPU-only PyTorch достаточно для всех ML-методов (CUDA не требуется), обучение на CPU занимает часы.

### Bao — [BaoForPostgreSQL](https://github.com/learnedsystems/BaoForPostgreSQL)

```bash
git clone https://github.com/learnedsystems/BaoForPostgreSQL ~/BaoForPostgreSQL
cd ~/BaoForPostgreSQL/pg_extension && make USE_PGXS=1 install
initdb -D ~/bao_pgdata
pg_ctl -D ~/bao_pgdata -o "-p 5500" start
psql -p 5500 postgres -c "CREATE EXTENSION pg_bao"
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r ~/BaoForPostgreSQL/bao_server/requirements.txt
export CUDA_VISIBLE_DEVICES=""
cd ~/BaoForPostgreSQL/bao_server && python main.py   # слушает на :9381
```

Затем повторить `job_create.sh` против порта 5500, чтобы залить IMDb в кластер Bao. Bao идёт со своим форком PG (модифицирует планировщик), `pg_bao` нельзя загрузить в ванильный PG. Marcus et al., SIGMOD 2021.

Скрипт [job_run_bao.sh](job_run_bao.sh) проверяет, что `bao_server` слушает `http://localhost:9381` — иначе `pg_bao` молча уходит в дефолтный планировщик, и метрики были бы про PG, а не про Bao.

### Neo — [KostasMparmparousis/Neo](https://github.com/KostasMparmparousis/Neo)

Официального кода от Marcus et al. (VLDB 2019) нет, поэтому используется community-реимплементация. В 2022+ Neo фактически вытеснен Balsa — если выбираете один из двух, берите Balsa.

```bash
git clone https://github.com/KostasMparmparousis/Neo ~/neo
# Соберите PG14 c pg_hint_plan:
git clone https://github.com/ossc-db/pg_hint_plan ~/pg_hint_plan
cd ~/pg_hint_plan && make PG_CONFIG=~/neo_pg/inst/bin/pg_config install
initdb -D ~/neo_pgdata
pg_ctl -D ~/neo_pgdata -o "-p 5501" start
echo "shared_preload_libraries = 'pg_hint_plan'" >> ~/neo_pgdata/postgresql.conf
pg_ctl -D ~/neo_pgdata restart
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r ~/neo/requirements.txt
export CUDA_VISIBLE_DEVICES=""
# Обучить Neo на train-split JOB, затем сгенерировать хинты:
#   ~/neo/hints/<query>.hint   <- pg_hint_plan-строка для каждого запроса
```

[job_run_neo.sh](job_run_neo.sh) читает хинт из `$NEO_HINTS_DIR/<query>.hint`, грузит `pg_hint_plan`, склеивает хинт + SQL, замеряет.

### Balsa — [balsa-project/balsa](https://github.com/balsa-project/balsa)

Yang et al., SIGMOD 2022. Преемник Neo, обучается без expert-демо.

```bash
git clone https://github.com/balsa-project/balsa ~/balsa
cd ~/balsa
./scripts/build_pg.sh    # собирает PG14 с pg_hint_plan и патчем Balsa -> ~/balsa/inst/
./scripts/init_db.sh     # кластер на порту 5502
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r ~/balsa/requirements.txt
export CUDA_VISIBLE_DEVICES=""
python -m balsa.train --workload=job --device=cpu
# Balsa пишет per-query хинты в ~/balsa/hints/job/<query>.hint
```

[job_run_balsa.sh](job_run_balsa.sh) применяет хинт + замеряет через `pg_hint_plan` ровно так же, как Neo.

### SkinnerDB — [cornelldbgroup/skinnerdb](https://github.com/cornelldbgroup/skinnerdb)

Trummer et al., SIGMOD 2019. Самостоятельный Java DBMS — **PostgreSQL не используется**.

```bash
git clone https://github.com/cornelldbgroup/skinnerdb ~/SkinnerDB
cd ~/SkinnerDB && mvn package
# Загрузить IMDb во встроенное хранилище SkinnerDB:
java -jar target/skinnerdb-1.0-SNAPSHOT-jar-with-dependencies.jar \
     --load /home/alena/min_job/source/csv
```

[job_run_skinner.sh](job_run_skinner.sh) шлёт SQL в jar по stdin и парсит строку `Query took XXX ms`. Ни `\timing`, ни `pg_hint_plan` тут не работают.

---

## Замечания

- Все `job_run_*.sh` пишут CSV с одинаковым форматом `query,iter,exec_ms`, поэтому [collect.sh](collect.sh) автоматически подхватывает любой новый метод — достаточно положить файл в `results/<method>_job.csv`.
- Bao замеряется как «plain» wallclock (`\timing`) — это total cost (planning + exec), Bao подсовывает хинты через `planner_hook`. Neo и Balsa замеряются с уже подготовленными хинтами, время инференса в `exec_ms` не входит.
- Деплой IMDb тестировался только на C-locale (см. [source/README.md](source/README.md)).
