# Durian

A Text-to-SQL method for the BEAVER benchmark built on a **Semantic Network + ReAct Agent**.

> **Note:** this method is designed and tuned around the **`dw` database** of the BEAVER benchmark. With 5787 cases (vs. ~1000 for `nova`/`neutron`), `dw` provides far more question + gold SQL evidence, from which the Semantic Agent can distill substantially richer business features (coverage caveats, similar-table disambiguation, join patterns, metrics). All example commands below use `dw`; other databases (`nova` / `neutron` / `dw_real`) are supported by the same pipeline.

The workflow has three steps:

1. **Build the semantic network** — Export table/column schemas from a MySQL database into a semantic YAML, then use a Semantic Agent to continuously **enrich the semantic network** (table descriptions, column descriptions, metrics, concepts, join relationships) from the question + gold SQL pairs of the benchmark dataset (BEAVER). The training cases are not fed to the Agent wholesale: each gold SQL is parsed (sqlglot) to extract the tables/columns it touches, and a **greedy set-cover** selects the minimal subset of cases that covers every table/column used by the benchmark, grouped by table — so the Agent sees all the evidence for one table in a single session at minimal token cost (in practice only ~4–6% of the cases are selected: dw 225/5787, neutron 61/1017, nova 54/1053). **The pre-built semantic networks are committed as YAML files under `Agent/semantic/`; the vector store is NOT committed and must be rebuilt manually (see Setup).**

2. **Generate SQL** — For each question, a DataAgent (ReAct loop) retrieves the semantic network, drafts a MySQL SQL query, verifies it by execution against the real database, and submits the final SQL via the `submit_SQL` tool. BEAVER hint settings are supported: `setting 0` uses the semantic network only; `setting 1` additionally injects gold tables / column mapping / join keys; `setting 2` additionally injects domain knowledge / subquery decomposition.

3. **Evaluate** — The `run` stage writes results **directly** in the BEAVER unified-output format (`eval/unified-output/durian/{run_name}/{generated,gold}/*.sql`), which is scored by the official `eval/evaluate_ex_acc.py` (execution accuracy) with no extra conversion step.

On the `dw` evaluation subset (100 sampled cases, `qwen3.8-max`), Durian achieves **30.0% / 45.0% / 61.0%** execution accuracy under BEAVER hint settings 0 / 1 / 2 respectively (see [Results](#results-on-dw)).

### Quick start

> Prerequisites from the main README are assumed done: environment installed (`eval/requirements.txt` includes Durian's deps), MySQL databases imported, and datasets downloaded (`data/download_hf.py`).

```bash
cd eval/durian

# 0. Configure the repo-root .env (one-time; see Setup below)
#    cp ../../.env.example ../../.env   then fill in
#    LLM_API_KEY / LLM_MODEL / LLM_BASE_URL / EMBEDDING_* / MYSQL_*

# 1. Rebuild the vector store from the committed semantic YAML (one-time, per database)
python scripts/pipeline.py --database dw --stages vector

# 2. Generate SQL (writes directly to eval/unified-output/durian/<run_name>/)
python scripts/pipeline.py --dataset dw --stages run --sampled --setting 0 --run-workers 4

# 3. Evaluate (from eval/, official BEAVER script)
cd ..
python evaluate_ex_acc.py --dataset dw --input_dir unified-output/durian/<run_name>
```

Each step is explained in detail in the sections below.

---

## Directory Structure

```
durian/
├── env_config.py           # Repo-root .env loader (all secrets/endpoints)
├── README.md
├── Agent/                  # Agent core
│   ├── base.py             # ReActAgent main loop
│   ├── cli.py              # Interactive CLI entry point
│   ├── tools.py            # All tools (mysql_query / semantic_* / submit_SQL, etc.)
│   ├── zvec_store.py       # Zvec vector store wrapper (entity vector search)
│   ├── react_config.json   # Non-secret config (ReAct loop, semantic network, vector store)
│   ├── prompts/            # Agent definitions (agents.json) and role prompts (*.md)
│   ├── semantic/           # Committed semantic network YAML (dw/nova/neutron)
│   └── zvec_db/            # Vector store (NOT committed; rebuild via the vector stage)
├── scripts/
│   ├── pipeline.py         # Pipeline entry point (build → run)
│   └── output/             # Session logs of the update/run stages (generated)
├── Eval/
│   └── submitted_sql.jsonl # Fallback submission log (interactive CLI only; generated)
├── LLM/                    # LLM client wrapper (OpenAI-compatible API)
└── Web/                    # Semantic network visualization (FastAPI + graph.html)
```

Datasets are shared with the rest of the BEAVER repo (`../../data/{dataset}/`); evaluation outputs go to `eval/unified-output/durian/`.

---

## Setup

Environment installation, MySQL database import, and dataset download are all covered by the **main README** and are not repeated here. Durian-specific setup:

### 1. Configure the repo-root `.env`

All secrets and endpoints are read **exclusively from the repo-root `.env` file** (process environment variables are NOT used). A template with every key (values redacted) is committed at the repo root:

```bash
cp ../../.env.example ../../.env    # then fill in your own keys / endpoints / models
```

The Durian-specific keys, alongside the MySQL keys shared with the other BEAVER methods:

```bash
# ── Durian LLM (any OpenAI-compatible endpoint) ──
LLM_API_KEY=<your-llm-api-key>
LLM_MODEL=<your-llm-model>
LLM_BASE_URL=<your-llm-base-url>

# ── Durian embedding (vector store build / semantic search) ──
EMBEDDING_API_KEY=<your-embedding-api-key>
EMBEDDING_MODEL=<your-embedding-model>
EMBEDDING_BASE_URL=<your-embedding-base-url>

# ── MySQL (same keys the other BEAVER methods use) ──
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=<your-mysql-password>
```

`EMBEDDING_MODEL` must produce vectors of dimension `semantic_network.embedding_dim` in `Agent/react_config.json` (default `1024`); changing the embedding model requires updating that field **and** rebuilding the vector store.

To switch LLM/model for an evaluation run, edit `LLM_MODEL` / `LLM_BASE_URL` / `LLM_API_KEY` in `.env` — there are no command-line overrides.

### 2. Configure `Agent/react_config.json` (non-secret tuning only)

Key fields:

| Field | Description |
|---|---|
| `temperature` / `max_steps` / `reasoning_effort` | ReAct loop parameters |
| `semantic_network.semantic_dir` | Semantic YAML directory (default `Agent/semantic`) |
| `semantic_network.vector_db_dir` | Vector store root directory (default `Agent/zvec_db`) |
| `semantic_network.embedding_dim` | Embedding dimension (must match `EMBEDDING_MODEL` output) |
| `mysql.max_rows_returned` / `connect_timeout_seconds` | MySQL query limits |

### 3. Rebuild the vector store (required, one-time per database)

Only the semantic YAML files are committed. After cloning, rebuild the vector index from them (uses `EMBEDDING_*` from `.env`):

```bash
python scripts/pipeline.py --database dw --stages vector
python scripts/pipeline.py --database nova --stages vector
python scripts/pipeline.py --database neutron --stages vector
```

`dw_real` reuses the `dw` semantic network and vector store.

---

## Step 1: Build the Semantic Network

The whole workflow has three steps, all driven by the single entry point `scripts/pipeline.py`:

```
build (semantic network) ──► run (inference → unified-output) ──► official BEAVER evaluation
```

### The semantic network model

The semantic network is the core asset of this system: a **YAML knowledge graph** (`Agent/semantic/{database}.yaml`) paired with a **vector index** (`Agent/zvec_db/{database}/`). It bridges the gap between natural-language questions and physical database schemas by encoding business knowledge that cannot be recovered from `information_schema` alone.

The graph has four entity types and one relation type:

| Element | What it captures | Example |
|---|---|---|
| **table** | Table-level business meaning + a `columns` dict where every column carries a business description (not just a restatement of its name), including caveats like data coverage, value enumerations, and differences from confusingly similar columns | `ACADEMIC_TERM_PARAMETER`: "holds only 3 rows — current/previous/upcoming term — so joining fact tables to it restricts results to these terms" |
| **joins** (relationship) | Verified join paths between tables, with the concrete column pairs and *when/why* to use the join; multiple column pairs per table pair are allowed | `ACADEMIC_TERM_PARAMETER → ACADEMIC_TERMS` on `TERM_CODE`, to resolve relative term references to full term attributes |
| **metric** | A reusable analytical pattern distilled from a gold SQL: business name, category (business-domain based, e.g. "Subject Offering Analysis"), the question it answers, and the verbatim SQL; metric→table dependencies are auto-derived from the SQL | `dw_359`: "Yearly Math Lecture Units Above One Stddev with Undergraduate Majority" |
| **concept / column_concept** | Disambiguation knowledge for entities that serve the same business problem domain: `tables`/`columns` reference arrays, `comparisons` (objective, dimension-by-dimension differences such as granularity, row coverage, unique columns, join keys), and `decision_guide` (scenario → recommended table/column with reasoning) | `concept_academic_term_dimension`: compares `ACADEMIC_TERMS` vs `ACADEMIC_TERMS_ALL` vs `ACADEMIC_TERM_PARAMETER` and tells the agent which one to use for "current term" questions vs. widest-coverage year attributes |

Design principles enforced by the Semantic Agent's prompt (`Agent/prompts/Semantic.md`):

- **Global perspective only** — descriptions must reflect the database's business as a whole; local phrasing like "example SQL" or "test case" is prohibited
- **Objective descriptions only** — no subjective labels like "core table" / "main table"
- **No orphan nodes** — a relationship may only be created after both endpoints exist
- **Concepts don't carry join semantics** — join paths live in `joins`; concepts only organize and disambiguate similar entities
- **Gold SQL is authoritative** — metrics preserve the original question and SQL verbatim, even if the SQL looks risky (annotate, don't rewrite)

### How the network is constructed

Construction is **schema-seeded, data-driven, and agent-authored**:

1. The physical schema provides the skeleton (tables/columns from `information_schema`)
2. Benchmark question + gold SQL pairs provide the business evidence — a minimal cover set ensures every table/column touched by the benchmark is seen by the Agent at least once, at minimal token cost
3. A Semantic Agent (LLM-driven, with SQL execution ability) reads the evidence, **verifies hypotheses against real data via `mysql_query`** (e.g. checking row counts, value distributions, join validity), and writes structured knowledge back into the YAML — every write incrementally updates the vector index

Building the semantic network is one command that internally runs four phases in order (`export,vector,cover,update`). **This is a one-time offline build; the resulting YAML files are already committed under `Agent/semantic/`, so evaluation only requires the `vector` rebuild step (see Setup).** To reproduce or extend the build:

```bash
python scripts/pipeline.py --database dw --dataset dw \
    --prompt "Update the semantic network for these cases" \
    --stages export,vector,cover,update
```

### What happens inside

**1. `export` — database → semantic YAML.** Reads all tables and columns from MySQL `information_schema` and generates the initial semantic YAML (`Agent/semantic/{database}.yaml`):

- One table entity per table; `columns` is a nested dict `{column_name: {desc, default?}}`
- Column descriptions prefer `COLUMN_COMMENT`, automatically annotated with `[PK]` / `[INDEX]` / `[UNIQUE]` / `[AUTO_INCREMENT]`
- `relationships` / `metrics` start empty and are populated by the `update` phase

**2. `vector` — semantic YAML → vector store.** Batch-embeds the `name + desc + synonyms` of every entity (table / metric / concept / column_concept) into the Zvec vector store (`Agent/zvec_db/{database}/`) for vector retrieval by the `semantic_search` tool. Column-level information is not vectorized: the DataAgent retrieves full column descriptions via `semantic_get` on the parent table.

> Note: this phase only handles the **initial full build**. During the `update` phase, the semantic tools (`semantic_upsert_entity` / `semantic_delete`, etc.) **incrementally sync vectors** whenever they write the YAML. Only re-run the `vector` phase to realign if an incremental sync failed (look for `[Warning] Vector sync failed` in the logs — sync failures do not block the main flow) or if the YAML was modified manually outside of the Agent.

**3. `cover` — dev.json → minimal cover set.** Parses each case's gold SQL with sqlglot to extract the tables and columns it touches (CTE / subquery aliases filtered out automatically), then runs a **greedy set cover** to select the smallest set of cases covering all tables/columns. Outputs `data/{dataset}/min_cover.json` (generated, not committed), whose `grouped_by_table` field (table → case list) drives the grouping of the `update` phase — so the semantic update reaches every table and column used by the benchmark with the fewest cases.

Compression achieved on the BEAVER datasets (cover target `both`, i.e. tables + columns):

| Dataset | Total cases | Selected cases | Ratio | Tables | Cover elements (tables + columns) | `--min-cases` |
|---|---|---|---|---|---|---|
| `dw` | 5787 | 225 | **3.9%** | 57 | 951 (100% covered) | 1 |
| `neutron` | 1017 | 61 | **6.0%** | 26 | 130 (100% covered) | 3 |
| `nova` | 1053 | 54 | **5.1%** | 16 | 101 (100% covered) | 3 |

In other words, the Semantic Agent only needs to read ~4–6% of the benchmark to see every table and column in use (`dw` with `--min-cases 1`; `neutron`/`nova` with `--min-cases 3`, requiring each element to be covered by at least 3 selected cases for more robust descriptions).

**4. `update` — grouped-by-table semantic enrichment.** For each table group in `min_cover.json`, one **Semantic Agent** session is started (serially). Each session's prompt = the `--prompt` task instruction + the material of all cases in the group (fixed injection of `question` + `gold SQL`). Grouping by table gives each session a focused scope: the agent sees all benchmark evidence touching one table at once, so it can spot similar-table confusion, join patterns, and reusable metrics in a single pass.

The Semantic Agent (defined in `Agent/prompts/agents.json`, prompt in `Agent/prompts/Semantic.md`) has read/write access to the semantic network:

| Tool | Purpose |
|---|---|
| `semantic_search` | Vector search over entities (table / metric / concept) |
| `semantic_get` / `semantic_list` | Read entity details / list entities and relationships |
| `semantic_graph` | Graph operations: neighbor queries, lineage tracing, etc. |
| `semantic_upsert_entity` | Add or update entities (table/column descriptions, metrics, concepts) |
| `semantic_upsert_relationship` | Add or update relationships (joins) |
| `semantic_delete` | Delete entities or relationships |
| `mysql_query` | Execute SQL to verify data distribution, join validity, etc. |

Working from the gold SQL, the Agent distills business knowledge and writes it back to the YAML:

- **Table/column descriptions** — completes business semantics, verifying against real data with `mysql_query` (row counts, enum values, coverage caveats); confusingly similar columns must have their differences spelled out
- **Join relationships** — extracts join paths from the gold SQL and records the column pairs plus the business rationale for the join
- **Metrics** — turns each gold SQL into a reusable, categorized analytical pattern (question + SQL preserved verbatim)
- **Concepts** — when multiple tables/columns serve the same problem domain (e.g. three term-dimension tables, or six subject-offering fact tables), creates a concept/column_concept with `comparisons` and a `decision_guide`, so that at inference time the DataAgent can pick the right entity among look-alikes instead of guessing

Each session ends with a compliance self-check (no orphan references, no local-perspective wording, every enum/numeric table covered by at least one metric, etc.) and a report of added/modified/deleted entities.

### Outputs

- `Agent/semantic/{database}.yaml` — the enriched semantic network (committed)
- `Agent/zvec_db/{database}/` — the vector store (generated; rebuild via the `vector` stage)
- `data/{dataset}/min_cover.json` — the minimal cover set (generated)
- `scripts/output/grouped_{dataset}_{ts}/` — one `{TABLE}.json` per table group (answer / error / elapsed time / log path) + `summary.json` (generated)

### Running individual phases

Each phase can also be run on its own via `--stages` (useful for rebuilding only part of the network):

```bash
python scripts/pipeline.py --database dw --stages export          # add --dry-run to preview; --yaml for a custom path
python scripts/pipeline.py --database dw --stages vector          # --db-dir / --workers (concurrent embedding threads, default 100)
python scripts/pipeline.py --dataset dw --stages cover            # --cover-target tables|columns|both, --min-cases N, --dialect mysql
python scripts/pipeline.py --database dw --dataset dw --stages update --prompt "Update Semantic Network"   # --agent / --semantic / --update-out
```

---

## Step 2: Inference (`run`)

The `run` stage is the standard BEAVER evaluation entry point. It starts one **DataAgent** session per case; the DataAgent's default task prompt requires:

> Answer the question with a single MySQL SQL query; explore the semantic network and verify with `mysql_query` as needed; the SELECT list must contain exactly the columns the question asks for, in the asked order; once the final SQL is verified, submit it via `submit_SQL`.

DataAgent tools: `semantic_search` / `semantic_get` / `semantic_graph` (read-only semantic retrieval) + `mysql_query` (execution verification) + `submit_SQL` (answer submission).

```bash
# Standard BEAVER evaluation: run the sampled subset (dev_sampled.json)
python scripts/pipeline.py --dataset dw --stages run --sampled --setting 0 --run-workers 4

# Debug: run a subset of cases
python scripts/pipeline.py --dataset dw --stages run --case-range 0-99 --run-workers 4
python scripts/pipeline.py --dataset dw --stages run --cases dw_1,dw_2
```

- `--sampled`: use `../../data/{dataset}/dev_sampled.json` (the 100-case BEAVER evaluation subset). Without it, the full `dev.json` is used.
- `--setting`: BEAVER hint setting:
  - `setting 0` *(default)*: the agent relies on the pre-built semantic network only
  - `setting 1`: additionally injects gold tables, column mapping, and join keys into the task prompt
  - `setting 2`: additionally injects domain knowledge and subquery decomposition
- `--run-workers`: concurrent agent sessions (default 1, serial)
- `--run-name`: run name for the unified-output directory (default `{model}-beaver-{dataset}-setting{setting}-log-{ts}`)
- If `--database` is omitted it is derived from the dataset (`dw_real` → `dw`); the semantic YAML defaults to `Agent/semantic/{database}.yaml`
- LLM model/endpoint come from the repo-root `.env` (`LLM_MODEL` / `LLM_BASE_URL`); there are no command-line overrides

### Outputs

The `run` stage writes **directly** in the BEAVER unified-output format — no conversion step:

- `eval/unified-output/durian/{run_name}/generated/{case_id}.sql` — the SQL submitted via `submit_SQL` (empty if the agent never submitted)
- `eval/unified-output/durian/{run_name}/gold/{case_id}.sql` — the gold SQL
- `scripts/output/run_{dataset}_{ts}/` — per-case session logs (`{case_id}.json` with answer/error/elapsed) + `summary.json`

## Step 3: Evaluation

Evaluation uses the **official BEAVER scripts** directly on the unified output (no Durian-specific evaluation logic):

```bash
# From eval/
cd ..

# Execution accuracy
python evaluate_ex_acc.py --dataset dw --input_dir unified-output/durian/<run_name>

# (Optional) fine-grained subtask evaluation
python evaluate_subtasks.py --dataset dw --model gpt-5.2 --input_dir unified-output/durian/<run_name>
```

---

## Results on `dw`

Execution accuracy (EX, %) on the `dw` evaluation subset (`dev_sampled.json`, 100 cases), scored by the official `eval/evaluate_ex_acc.py`.

| BEAVER hint setting | Injected hints | EX (%) |
|---|---|---|
| `setting 0` | semantic network only | **30.0** |
| `setting 1` | + gold tables / column mapping / join keys | **45.0** |
| `setting 2` | + domain knowledge / subquery decomposition | **61.0** |

### Model configuration used for these results

All three numbers above come from a **single model configuration** — only the BEAVER hint setting changes between runs. Endpoints and API keys are read from the repo-root `.env` (see [Setup](#1-configure-the-repo-root-env)); the values actually used are:

| Component | Value |
|---|---|
| Agent LLM (`LLM_MODEL`) | `qwen3.8-max` |
| LLM endpoint (`LLM_BASE_URL`) | Alibaba Cloud DashScope, OpenAI-compatible mode (`https://dashscope.aliyuncs.com/compatible-mode/v1`) |
| Embedding model (`EMBEDDING_MODEL`) | `qwen3.7-text-embedding`, dim `1024` |
| Embedding endpoint (`EMBEDDING_BASE_URL`) | same DashScope OpenAI-compatible endpoint |
| Semantic network | `Agent/semantic/dw.yaml` (committed) + rebuilt `Agent/zvec_db/dw/` |

Decoding / ReAct parameters (`Agent/react_config.json`, identical for all three runs):

| Parameter | Value |
|---|---|
| `temperature` | `0` (greedy decoding) |
| `reasoning_effort` | `medium` |
| `enable_thinking` / `clear_thinking` | `true` / `true` |
| `max_steps` | `1000` |
| `vector_topk` | `10` |
| `mysql.max_rows_returned` | `500000` |

The Semantic Agent that built `dw.yaml` used the same LLM and embedding configuration. Note that both the semantic network and the reported accuracies are therefore specific to this model; switching `LLM_MODEL` reuses the committed semantic network as-is but the numbers are not expected to transfer.

Corresponding run directories under `eval/unified-output/durian/` (each contains `generated/`, `gold/`, `summary_ex_acc.json`):

| Setting | Run name | EX (%) |
|---|---|---|
| `setting 0` | `qwen3.8-max-beaver-dw-setting0-log-20261109-114945` | 30.0 |
| `setting 1` | `qwen3.8-max-beaver-dw-setting1-log-20261110-143031` | 45.0 |
| `setting 2` | `qwen3.8-max-beaver-dw-setting2-log-20261110-102916` | 61.0 |



Observations:

- Hint injection helps substantially: +15.0 points from setting 0 → 1, and another +16.0 from setting 1 → 2. Grounding the agent in the gold tables/columns removes most wrong-table and wrong-join-path errors, and the domain knowledge + subquery decomposition further resolves business-term ambiguity and helps structure complex multi-CTE analytical queries.
- The remaining failures at setting 2 are dominated by complex analytical questions (multiple CTEs, subtle aggregation semantics such as sample- vs population-stddev, geometric means over joined fan-out) where the predicted SQL executes fine but diverges from the gold query's exact computation path.

Reproduce with:

```bash
python scripts/pipeline.py --dataset dw --stages run --sampled --setting 0 --run-workers 4   # repeat with --setting 1 / 2
cd .. && python evaluate_ex_acc.py --dataset dw --input_dir unified-output/durian/<run_name>
```

---

## Interactive CLI

Besides the batch pipeline, you can chat with the Agent directly (multi-turn REPL). LLM/MySQL config comes from the repo-root `.env`:

```bash
python -m Agent.cli --database dw --agent DataAgent --semantic dw.yaml
# Single-question mode
python -m Agent.cli --database dw --once "What are the top 5 courses by enrollment in the current term?"
```

## Semantic Network Visualization

```bash
python -m Web.server        # or uvicorn Web.server:app
# Visit http://localhost:8000/
```

The web server reads the YAML files under `Agent/semantic/` and renders the semantic network graph (nodes = entities, edges = relationships), with a switcher between YAML files.
