#!/usr/bin/env python
"""Durian pipeline for the BEAVER benchmark (single entry point).

Stages (in order):
    1. export   db → YAML              (MySQL information_schema → semantic YAML)
    2. vector   YAML → vector store    (bulk-embed entity/column desc into Zvec)
    3. cover    dev.json → min cover   (greedy set-cover over tables/columns)
    4. update   grouped-by-table semantic update (one Agent session per table group)
    5. run      dev.json cases → DataAgent sessions (final SQL via submit_SQL)

All secrets and endpoints (LLM_API_KEY / LLM_MODEL / LLM_BASE_URL,
EMBEDDING_*, MYSQL_*) are read exclusively from the repo-root `.env` file
(see env_config.py); process environment variables are NOT used.

The `run` stage writes results DIRECTLY in the BEAVER unified-output format:
    eval/unified-output/durian/{run_name}/generated/{case_id}.sql   (submitted SQL)
    eval/unified-output/durian/{run_name}/gold/{case_id}.sql        (gold SQL)
so the official evaluators can consume them without any conversion:
    cd .. && python evaluate_ex_acc.py --dataset dw --input_dir unified-output/durian/{run_name}

Runs all stages in order by default, or run individual stages via --stages.

Usage (from eval/durian):
    # All stages (export/vector/cover need no extra args; update requires --prompt)
    python scripts/pipeline.py --database dw --dataset dw --prompt "Update the semantic network for these cases"

    # Standard BEAVER evaluation flow: inference on dev_sampled.json
    python scripts/pipeline.py --dataset dw --stages run --sampled --setting 0 --run-workers 4

    # Run specific stages only (comma-separated)
    python scripts/pipeline.py --database dw --stages export,vector
    python scripts/pipeline.py --dataset dw --stages cover
    python scripts/pipeline.py --database dw --dataset dw --stages update --prompt "..."
    python scripts/pipeline.py --dataset nova --stages run --case-range 0-9 --setting 0

Options (grouped by stage):
    global:
    --stages         stages to run (comma-separated: export,vector,cover,update,run; default all in order)
    --dataset        dataset name (for cover/update/run, default dw)
    --database       MySQL database name (required for export/update; run derives it from dataset if omitted)
    --yaml           semantic YAML path (default Agent/semantic/{database}.yaml)
    --dev            dev.json path (default ../../data/{dataset}/dev.json in the BEAVER repo)
    --sampled        use ../../data/{dataset}/dev_sampled.json instead (BEAVER evaluation subset)
    --dry-run        export/vector stages count only, do not write

    vector:
    --db-dir         vector store root directory (default Agent/zvec_db)
    --workers        concurrent embedding threads (default 100)

    cover:
    --cover-out      min_cover.json output path (default data/{dataset}/min_cover.json)
    --cover-target   cover target: tables/columns/both (default both)
    --dialect        sqlglot dialect (default mysql)
    --min-cases      each table/column covered by at least N selected cases (default 1)

    update:
    --prompt         task prompt (required; injected material fixed to question + sql)
    --agent          agent key (default Semantic)
    --semantic       semantic YAML file name (default: file name of --yaml)
    --update-out     result output directory (default scripts/output/grouped_{dataset}_{ts}/)

    run:
    --setting        BEAVER hint setting: 0=semantic network only (default),
                     1=+gold tables/column mapping/join keys, 2=+domain knowledge/decomposition
    --run-prompt     task prompt template (default built-in; {question} placeholder supported)
    --run-agent      agent key (default DataAgent)
    --cases          comma-separated case IDs to run (default: all in dev.json)
    --case-range     case index range like "0-9,20-29" (union with --cases)
    --run-workers    concurrent Agent sessions (default 1, serial)
    --run-name       run name for the unified-output directory
                     (default {model}-beaver-{dataset}-setting{setting}-log-{ts})
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import time
from pathlib import Path
from typing import Any

# Ensure Agent/LLM packages are importable (project root)
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# BEAVER repo root (eval/durian -> eval -> repo root) and shared data directory
BEAVER_ROOT = PROJECT_ROOT.parent.parent
BEAVER_DATA = BEAVER_ROOT / "data"

# All secrets/endpoints (LLM_*, EMBEDDING_*, MYSQL_*) are read exclusively
# from the repo-root .env file via env_config (no process-env fallback).

CONFIG_PATH = PROJECT_ROOT / "Agent" / "react_config.json"

ALL_STAGES = ("export", "vector", "cover", "update", "run")

STAGE_DESC = {
    "export": "db → YAML (information_schema → semantic YAML)",
    "vector": "YAML → vector store (bulk embed into Zvec)",
    "cover": "dev.json → min cover set (greedy set-cover)",
    "update": "grouped-by-table semantic update (Agent sessions)",
    "run": "dev.json cases → DataAgent sessions (submit_SQL → unified-output)",
}

DEFAULT_RUN_PROMPT = (
    "Answer the following question with a single MySQL SQL query against the current database. "
    "Explore the semantic network and verify with mysql_query as needed. "
    "The SELECT list must contain exactly the columns the question asks for, in the asked order. "
    "When the final SQL is verified, call the submit_SQL tool with it.\n\n"
    "{hints}"
    "## Question\n{question}"
)


def _build_setting_hints(case: dict[str, Any], setting: int) -> str:
    """Build the hint block for BEAVER settings 1/2 (empty for setting 0).

    setting 1: gold tables + column mapping + join keys
    setting 2: setting 1 + domain knowledge + subquery decomposition
    """
    if setting <= 0:
        return ""
    parts: list[str] = []
    tables = case.get("tables") or []
    if tables:
        clean = [t.split("#sep#")[1] if "#sep#" in t else t for t in tables]
        parts.append("## Gold Tables\n" + "\n".join(f"- {t}" for t in clean))
    cm = case.get("column_mapping") or {}
    if cm:
        cm_lines = []
        for phrase, refs in cm.items():
            if isinstance(refs, str):
                refs = [refs]
            cm_lines.append(f"- {phrase}: {', '.join(refs)}")
        parts.append("## Column Mapping\n" + "\n".join(cm_lines))
    jk = case.get("join_keys") or []
    if jk:
        jk_lines = [f"- {' <-> '.join(pair)}" if isinstance(pair, list) else f"- {pair}" for pair in jk]
        parts.append("## Join Keys\n" + "\n".join(jk_lines))
    if setting >= 2:
        dk = case.get("domain_knowledge") or []
        if dk:
            parts.append("## Domain Knowledge\n" + "\n".join(f"- {k}" for k in dk))
        sub_questions = case.get("sub_questions") or []
        sub_sqls = case.get("sub_sqls") or []
        if sub_questions or sub_sqls:
            dec_lines = []
            for i in range(max(len(sub_questions), len(sub_sqls))):
                q = sub_questions[i] if i < len(sub_questions) else ""
                s = sub_sqls[i] if i < len(sub_sqls) else ""
                dec_lines.append(f"{i + 1}. {q}\n```sql\n{s}\n```")
            parts.append("## Subquery Decomposition\n" + "\n".join(dec_lines))
    if not parts:
        return ""
    return "The following hints are provided to help you write the SQL:\n\n" + "\n\n".join(parts) + "\n\n"

_print_lock = threading.Lock()


def log(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


def _resolve(path_str: str) -> str:
    """Resolve relative paths against the project root; return a string."""
    p = Path(path_str)
    if not p.is_absolute():
        p = (PROJECT_ROOT / p).resolve()
    return str(p)


# ===========================================================================
# Stage 1: export (db → YAML)
# ===========================================================================

def _get_mysql_connection(database: str):
    """Build a MySQL connection from the repo-root .env (MYSQL_* keys)."""
    import mysql.connector

    from Agent.config_loader import build_mysql_config, load_config

    config_data = load_config(CONFIG_PATH)
    mysql_cfg = build_mysql_config(config_data)

    return mysql.connector.connect(
        host=mysql_cfg.host,
        port=mysql_cfg.port,
        user=mysql_cfg.user,
        password=mysql_cfg.password,
        database=database,
        connection_timeout=mysql_cfg.connect_timeout_seconds,
    )


def _fetch_all_tables(conn, database: str) -> list[dict[str, Any]]:
    """Query basic info of all tables from information_schema."""
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """
        SELECT
            TABLE_NAME,
            TABLE_COMMENT,
            TABLE_ROWS,
            ENGINE
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = %s
        ORDER BY TABLE_NAME
        """,
        (database,),
    )
    rows = cursor.fetchall()
    cursor.close()
    return rows


def _fetch_all_columns(conn, database: str) -> dict[str, list[dict[str, Any]]]:
    """Query all columns from information_schema, grouped by table name."""
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        """
        SELECT
            TABLE_NAME,
            COLUMN_NAME,
            COLUMN_TYPE,
            DATA_TYPE,
            IS_NULLABLE,
            COLUMN_KEY,
            COLUMN_DEFAULT,
            COLUMN_COMMENT,
            EXTRA,
            ORDINAL_POSITION
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = %s
        ORDER BY TABLE_NAME, ORDINAL_POSITION
        """,
        (database,),
    )
    rows = cursor.fetchall()
    cursor.close()

    columns_by_table: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        table_name = row["TABLE_NAME"]
        if table_name not in columns_by_table:
            columns_by_table[table_name] = []
        columns_by_table[table_name].append(row)
    return columns_by_table


def _build_table_entity(
    table_row: dict[str, Any],
    columns: list[dict[str, Any]],
) -> dict[str, Any]:
    """Build one table entity (with nested columns).

    Columns are nested inside the table entity as structural info; they are not
    independent semantic-network entities.
    """
    table_name = table_row["TABLE_NAME"]

    # Build desc: only state the field count
    desc = f"{len(columns)} columns in total"

    # Build column dict: key = column name, value = {desc, default?}
    col_dict: dict[str, Any] = {}
    for col in columns:
        col_name = col["COLUMN_NAME"]
        col_comment = str(col.get("COLUMN_COMMENT", "")).strip()
        col_key = str(col.get("COLUMN_KEY", "")).strip()
        col_default = col.get("COLUMN_DEFAULT")
        extra = str(col.get("EXTRA", "")).strip()

        # Column description: prefer the comment, leave empty if none
        col_desc = col_comment if col_comment else ""

        # Annotate primary key / index / unique
        if col_key == "PRI":
            col_desc = f"[PK] {col_desc}".strip()
        elif col_key == "MUL":
            col_desc = f"[INDEX] {col_desc}".strip()
        elif col_key == "UNI":
            col_desc = f"[UNIQUE] {col_desc}".strip()

        # Annotate auto_increment
        if "auto_increment" in extra.lower():
            col_desc = f"[AUTO_INCREMENT] {col_desc}".strip()

        col_entry: dict[str, Any] = {"desc": col_desc}
        if col_default is not None:
            col_entry["default"] = str(col_default)

        col_dict[col_name] = col_entry

    return {
        "id": table_name,
        "name": table_name,
        "desc": desc,
        "columns": col_dict,
    }


def _build_yaml_doc(
    database: str,
    tables: list[dict[str, Any]],
    columns_by_table: dict[str, list[dict[str, Any]]],
) -> dict[str, Any]:
    """Build the full YAML document structure."""
    table_entities = []
    for table_row in tables:
        table_name = table_row["TABLE_NAME"]
        cols = columns_by_table.get(table_name, [])
        table_entities.append(_build_table_entity(table_row, cols))

    return {
        "version": 1,
        "database": database,
        "tables": table_entities,
        "relationships": [],
        "metrics": [],
    }


def run_export(args: argparse.Namespace, yaml_path: str) -> int:
    """Export all tables of a MySQL database into a semantic-network YAML."""
    import yaml

    database = args.database
    output_path = Path(yaml_path)

    print(f"Connecting to database: {database} ...")
    conn = _get_mysql_connection(database)
    print("Connected.")

    print("Fetching all tables ...")
    tables = _fetch_all_tables(conn, database)
    print(f"Found {len(tables)} tables.")

    print("Fetching all columns ...")
    columns_by_table = _fetch_all_columns(conn, database)
    total_columns = sum(len(cols) for cols in columns_by_table.values())
    print(f"Found {total_columns} columns.")

    conn.close()
    print("Database connection closed.")

    doc = _build_yaml_doc(database, tables, columns_by_table)

    # Print statistics
    print("\n" + "=" * 60)
    print(f"Database: {database}")
    print(f"Tables: {len(doc['tables'])}")
    print(f"Total columns: {total_columns}")
    print(f"Relationships: {len(doc['relationships'])}")
    print(f"Metrics: {len(doc['metrics'])}")
    print("=" * 60)

    # Preview the first 5 tables
    print("\nPreview of first 5 tables:")
    for table in doc["tables"][:5]:
        col_count = len(table.get("columns", []))
        print(f"  - {table['id']}: {col_count} columns | {table['desc'][:80]}")

    if args.dry_run:
        print("\n[--dry-run] YAML not written.")
        return 0

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False, default_flow_style=False)

    print(f"\nWritten to: {output_path}")
    return 0


# ===========================================================================
# Stage 2: vector (YAML → vector store)
# ===========================================================================

def _build_vector_tool(yaml_path: str, db_dir: str):
    """Build a SemanticNetworkTool with a YAML namespace."""
    from Agent.config_loader import build_semantic_config, load_config
    from Agent.tools import SemanticNetworkTool

    config_data = load_config(CONFIG_PATH)
    cfg = build_semantic_config(config_data)
    cfg.yaml_path = yaml_path
    cfg.vector_db_dir = db_dir
    return SemanticNetworkTool(cfg)


def _bulk_index(
    yaml_path: str,
    db_dir: str,
    dry_run: bool = False,
    max_workers: int = 100,
) -> dict:
    """Index all entities of one YAML file (concurrent embedding + serial writes)."""
    tool = _build_vector_tool(str(yaml_path), db_dir)
    doc = tool._load()
    tool._ensure_collections(doc)
    effective_db_dir = tool._vector_db_dir_for_yaml() or db_dir

    # Collect all entities
    all_items: list[tuple[str, str, str, str, list[str] | None]] = []  # (etype, eid, name, desc, synonyms)
    stats: dict[str, int] = {}
    skipped = 0

    for etype, entity in tool._iter_all_entities(doc):
        eid = str(entity.get("id", ""))
        name = str(entity.get("name", ""))
        desc = str(entity.get("desc", ""))
        synonyms_raw = entity.get("synonyms", [])
        synonyms = [str(s) for s in synonyms_raw if s] if isinstance(synonyms_raw, list) else None
        stats[etype] = stats.get(etype, 0) + 1

        if not name and not desc:
            skipped += 1
            continue

        all_items.append((etype, eid, name, desc, synonyms))

    total = len(all_items)
    print(f"\n{'[DRY-RUN] ' if dry_run else ''}Indexing: {yaml_path}")
    print(f"  Vector dir: {effective_db_dir}")
    print(f"  Total: {total} entities (skipped {skipped} with empty desc)")
    for etype, count in sorted(stats.items()):
        print(f"    {etype}: {count}")

    if dry_run:
        return {"total": total, "skipped": skipped, "errors": 0, "elapsed": 0.0}

    # Get vector store
    store = tool._get_vector_store()
    if store is None:
        print("  [ERROR] Vector store not enabled")
        return {"total": total, "skipped": skipped, "errors": total, "elapsed": 0.0}

    t0 = time.time()

    # Progress bar callback: refresh in real time per completed item
    def _on_progress(d: int, t: int, e: int) -> None:
        elapsed = time.time() - t0
        rate = d / elapsed if elapsed > 0 else 0
        eta = (t - d) / rate if rate > 0 else 0
        bar_len = 30
        filled = int(bar_len * d / t) if t > 0 else 0
        bar = "█" * filled + "░" * (bar_len - filled)
        pct = d * 100 // t if t > 0 else 0
        print(
            f"\r  [{bar}] {pct:3d}% {d}/{t} "
            f"({rate:.1f}/s, ETA {eta:.0f}s, errors {e})",
            end="",
            flush=True,
        )

    r = store.batch_upsert(all_items, max_workers=max_workers, on_progress=_on_progress)
    success = r.get("success", 0)
    errors = r.get("errors", 0)

    elapsed = time.time() - t0
    print()  # newline
    print(f"  Indexing done: entities success {success}, errors {errors}, elapsed {elapsed:.1f}s")
    return {"total": total, "skipped": skipped, "errors": errors, "elapsed": elapsed}


def run_vector(args: argparse.Namespace, yaml_path: str) -> int:
    """Bulk-embed all entities of the semantic YAML into the Zvec vector store."""
    if not Path(yaml_path).exists():
        print(f"YAML file not found: {yaml_path}", file=sys.stderr)
        return 1
    db_dir = _resolve(args.db_dir)
    _bulk_index(yaml_path, db_dir, dry_run=args.dry_run, max_workers=args.workers)
    return 0


# ===========================================================================
# Stage 3: cover (dev.json → min cover set)
# ===========================================================================

def _parse_sql_tables_columns(
    sql: str, dialect: str = "mysql"
) -> tuple[set[str], set[tuple[str, str]]]:
    """Parse one SQL with sqlglot, return (table set, (table, column) set).

    - CTE names are detected and filtered out (CTEs are not real tables).
    - FROM/JOIN alias mappings resolve column qualifiers back to real table names.
    - On parse failure, falls back to empty sets (does not block the pipeline).
    """
    import sqlglot
    from sqlglot import exp

    tables: set[str] = set()
    columns: set[tuple[str, str]] = set()

    if not sql or not sql.strip():
        return tables, columns

    try:
        parsed = sqlglot.parse(sql, dialect=dialect)
    except Exception:
        # Some SQL may be dialect-incompatible; retry without a dialect
        try:
            parsed = sqlglot.parse(sql)
        except Exception:
            return tables, columns

    for stmt in parsed:
        if stmt is None:
            continue
        _extract_from_ast(stmt, tables, columns, exp)

    return tables, columns


def _extract_from_ast(stmt, tables: set[str], columns: set[tuple[str, str]], exp) -> None:
    """Extract tables and columns from a single AST."""
    # 1. Collect CTE names (not real tables)
    cte_names: set[str] = set()
    for cte in stmt.find_all(exp.CTE):
        name = cte.alias_or_name
        if name:
            cte_names.add(name.upper())

    # 2. Collect real tables + build alias->table mapping
    #    CTE references (incl. aliases) go to cte_aliases to skip CTE-derived columns;
    #    derived-table (subquery) aliases also go to cte_aliases.
    alias_to_table: dict[str, str] = {}
    cte_aliases: set[str] = set()
    for t in stmt.find_all(exp.Table):
        nm = (t.name or "").strip()
        if not nm:
            continue
        nm_up = nm.upper()
        if nm_up in cte_names:
            cte_aliases.add(nm_up)
            alias = t.alias
            if alias:
                cte_aliases.add(alias.upper())
            continue
        tables.add(nm_up)
        alias_to_table[nm_up] = nm_up
        alias = t.alias
        if alias:
            alias_to_table[alias.upper()] = nm_up

    # Derived-table (subquery) aliases: their columns are not real table columns
    for sq in stmt.find_all(exp.Subquery):
        alias = sq.alias
        if alias:
            cte_aliases.add(alias.upper())

    # 3. Collect column references, resolve qualifiers
    for c in stmt.find_all(exp.Column):
        col = (c.name or "").strip().upper()
        if not col or col == "*":
            continue
        qual = (c.table or "").strip().upper()
        if qual:
            # Columns of CTE aliases/names: not real table columns, skip
            if qual in cte_aliases:
                continue
            resolved = alias_to_table.get(qual)
            if resolved is None:
                # Not a known alias: keep the qualifier as-is
                resolved = qual
            columns.add((resolved, col))
        else:
            # Unqualified column: cannot determine the owning table, skip
            continue

    # 4. Handle SELECT * / alias.* — only to confirm table existence
    for star in stmt.find_all(exp.Star):
        parent = star.parent
        if isinstance(parent, exp.Column):
            qual = (parent.table or "").strip().upper()
            if qual:
                resolved = alias_to_table.get(qual, qual)
                if resolved not in cte_names:
                    tables.add(resolved)


def _natural_sort_key(s: str) -> list:
    """Natural sort key: parse digit runs as int so dw_2 sorts before dw_10."""
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


def _greedy_set_cover(
    universe: set, cases: dict[str, set], min_count: int = 1
) -> list[str]:
    """Greedy approximate set cover (each element covered at least min_count times).

    Args:
        universe: set of elements to cover.
        cases: {case_id: elements covered by that case}.
        min_count: minimum number of selected cases covering each element (default 1).

    Returns:
        A minimal (approximate) list of case_ids satisfying the coverage requirement.
    """
    universe = set(universe)
    min_count = max(1, int(min_count))
    # Current coverage count per element from selected cases
    counts: dict = {elem: 0 for elem in universe}
    selected: list[str] = []
    remaining = {cid: set(elems) for cid, elems in cases.items()}

    def _satisfied() -> bool:
        return all(c >= min_count for c in counts.values())

    while not _satisfied():
        # Pick the case adding the most "effective coverage" (no gain past min_count)
        best_id, best_gain = None, -1
        for cid, elems in remaining.items():
            gain = sum(1 for e in elems if counts.get(e, 0) < min_count)
            if gain > best_gain or (gain == best_gain and best_id is not None and cid < best_id):
                best_gain = gain
                best_id = cid
        if best_id is None or best_gain <= 0:
            break  # Cannot cover further (some elements appear in < min_count cases)
        selected.append(best_id)
        for e in remaining[best_id]:
            if e in counts:
                counts[e] += 1
        del remaining[best_id]

    return selected


def run_cover(args: argparse.Namespace, dev_path: str, cover_out: str) -> int:
    """Build the minimal case set covering all tables/columns of dev.json."""
    in_path = Path(dev_path)
    if not in_path.exists():
        print(f"Input file not found: {in_path}", file=sys.stderr)
        return 1

    cases = json.loads(in_path.read_text(encoding="utf-8"))
    if not isinstance(cases, list):
        print("Input JSON is not an array", file=sys.stderr)
        return 1

    # 1. Extract tables/columns per case
    case_info: dict[str, dict] = {}
    all_tables: set[str] = set()
    all_columns: set[tuple[str, str]] = set()
    parse_errors: list[str] = []

    for case in cases:
        cid = case.get("id") or case.get("question")[:30]
        try:
            sql = case.get("sql") or ""
            tables, columns = _parse_sql_tables_columns(sql, dialect=args.dialect)
        except Exception as e:  # noqa: BLE001
            parse_errors.append(f"{cid}: {e}")
            tables, columns = set(), set()
        case_info[cid] = {
            "tables": tables,
            "columns": columns,
            "elements": set(),
        }
        all_tables |= tables
        all_columns |= columns

    # 2. Build the coverage universe
    universe: set = set()
    if args.cover_target in ("tables", "both"):
        universe |= {("table", t) for t in all_tables}
    if args.cover_target in ("columns", "both"):
        universe |= {("column", c) for c in all_columns}

    for cid, info in case_info.items():
        elems: set = set()
        if args.cover_target in ("tables", "both"):
            elems |= {("table", t) for t in info["tables"]}
        if args.cover_target in ("columns", "both"):
            elems |= {("column", c) for c in info["columns"]}
        info["elements"] = elems

    # 3. Greedy set cover (each element at least min_cases times)
    min_cases = max(1, args.min_cases)
    cases_for_cover = {cid: info["elements"] for cid, info in case_info.items()}
    selected = _greedy_set_cover(universe, cases_for_cover, min_count=min_cases)

    # 4. Coverage statistics (by count)
    elem_counts: dict = {elem: 0 for elem in universe}
    for cid in selected:
        for e in case_info[cid]["elements"]:
            if e in elem_counts:
                elem_counts[e] += 1
    covered = {e for e, c in elem_counts.items() if c >= 1}
    satisfied = {e for e, c in elem_counts.items() if c >= min_cases}
    missing = universe - covered
    insufficient = {e: elem_counts[e] for e in universe - satisfied if e in covered}

    # 5. Report
    print("=" * 70)
    print(f"Input file: {in_path}")
    print(f"sqlglot dialect: {args.dialect}")
    print(f"Total cases: {len(cases)}")
    print(f"Parse failures: {len(parse_errors)}")
    if parse_errors:
        for e in parse_errors[:10]:
            print(f"  ! {e}")
    print("-" * 70)
    print(f"Cover target: {args.cover_target}")
    print(f"Min cases per element: {min_cases}")
    print(f"Universe size: {len(universe)}  (tables {len(all_tables)}, columns {len(all_columns)})")
    print(f"Selected cases: {len(selected)}  "
          f"(compression {len(selected)/max(len(cases),1):.1%})")
    print(f"Covered (>=1): {len(covered)} / {len(universe)}  "
          f"({len(covered)/max(len(universe),1):.1%})")
    print(f"Satisfied (>={min_cases}): {len(satisfied)} / {len(universe)}  "
          f"({len(satisfied)/max(len(universe),1):.1%})")
    if missing:
        print(f"Uncovered elements: {len(missing)}")
        for m in sorted(missing)[:20]:
            print(f"  - {m}")
    if insufficient:
        print(f"Elements covered < {min_cases} times: {len(insufficient)}")
        for e, c in sorted(insufficient.items())[:20]:
            print(f"  - {e} (only {c})")
    print("-" * 70)
    print("Selected cases (first 50):")
    for cid in selected[:50]:
        info = case_info[cid]
        print(f"  {cid}: tables {len(info['tables'])}, columns {len(info['columns'])}, "
              f"covers {len(info['elements'])}")
    if len(selected) > 50:
        print(f"  ... {len(selected)} in total")
    print("-" * 70)
    # Group by table
    grouped: dict[str, set[str]] = {}
    for cid in selected:
        for tbl in case_info[cid]["tables"]:
            grouped.setdefault(tbl, set()).add(cid)
    print(f"Grouped by table: {len(grouped)} groups")
    for tbl in sorted(grouped):
        print(f"  {tbl}: {len(grouped[tbl])} cases")
    print("=" * 70)

    # 6. Write result
    out_path = Path(cover_out)

    # Group by table: table -> associated case list (natural-sorted IDs)
    grouped_by_table: dict[str, list[str]] = {}
    for cid in selected:
        for tbl in case_info[cid]["tables"]:
            grouped_by_table.setdefault(tbl, []).append(cid)
    grouped_by_table = {
        tbl: sorted(set(cids), key=_natural_sort_key)
        for tbl, cids in sorted(grouped_by_table.items())
    }

    result = {
        "input": str(in_path),
        "dialect": args.dialect,
        "cover": args.cover_target,
        "min_cases": min_cases,
        "total_cases": len(cases),
        "total_tables": sorted(all_tables),
        "total_columns": [list(c) for c in sorted(all_columns)],
        "universe_size": len(universe),
        "selected_cases": sorted(selected, key=_natural_sort_key),
        "selected_count": len(selected),
        "covered_count": len(covered),
        "satisfied_count": len(satisfied),
        "missing": [list(m) for m in sorted(missing)],
        "insufficient": [[list(e), c] for e, c in sorted(insufficient.items())],
        "grouped_by_table": grouped_by_table,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Result written to: {out_path}")
    return 0


# ===========================================================================
# Stage 4: update (grouped-by-table semantic update)
# ===========================================================================

def _load_cases(dev_path: Path) -> dict[str, dict[str, Any]]:
    """Load dev.json, return {case_id: case_dict}."""
    cases = json.loads(dev_path.read_text(encoding="utf-8"))
    return {str(c.get("id", "")): c for c in cases if c.get("id")}


def _load_grouped_by_table(cover_path: Path) -> dict[str, list[str]]:
    """Load the grouped_by_table grouping from min_cover.json."""
    data = json.loads(cover_path.read_text(encoding="utf-8"))
    return data.get("grouped_by_table") or {}


def _build_case_material(case: dict[str, Any]) -> str:
    """Generate the material snippet from case data (fixed injection: question + gold SQL)."""
    parts: list[str] = []
    question = case.get("question", "")
    parts.append(f"## Question\n{question}")
    sql = case.get("sql", "")
    parts.append(f"## Gold SQL\n```sql\n{sql}\n```")
    return "\n\n".join(parts)


def _build_group_prompt(group_cases: list[dict[str, Any]], prompt: str) -> str:
    """Build one table group's prompt: task prompt + all case material in the group."""
    parts: list[str] = []
    if prompt:
        parts.append(prompt)
    merged_parts = []
    for i, ct in enumerate(group_cases, 1):
        material = _build_case_material(ct["case"])
        if material:
            merged_parts.append(
                f"--- Case {i}/{len(group_cases)}: {ct['case_id']} ---\n\n{material}"
            )
    if merged_parts:
        parts.append("\n\n".join(merged_parts))
    return "\n\n".join(parts) if parts else ""


def _run_one_group(
    table_name: str,
    group_cases: list[dict[str, Any]],
    prompt: str,
    llm_config: Any,
    mysql_tool: Any,
    agent_key: str,
    semantic_file: str,
    database: str,
    out_dir: Path,
) -> dict[str, Any]:
    """Run one table group (single Agent session), return the result summary."""
    from Agent.base import ReActAgent
    from Agent.common import set_current_context, set_current_mysql_tool
    from Agent.context import AgentContext
    from LLM import build_client_from_env

    group_id = table_name
    started = time.time()

    set_current_context(AgentContext(
        semantic_file=semantic_file,
        database=database,
        case_id=group_id,
        session_id=f"group_{group_id}",
    ))
    set_current_mysql_tool(mysql_tool)

    agent = ReActAgent(
        client=build_client_from_env(llm_config),
        llm_config=llm_config,
        agent_key=agent_key,
    )

    log(f"[{group_id}] start ({len(group_cases)} cases)")

    error = ""
    answer = ""
    try:
        group_prompt = _build_group_prompt(group_cases, prompt)
        if group_prompt:
            answer = agent.run(group_prompt)
    except Exception as exc:  # noqa: BLE001
        error = str(exc)
        log(f"[{group_id}] error: {exc}")

    elapsed = time.time() - started
    result = {
        "table": table_name,
        "case_ids": [ct["case_id"] for ct in group_cases],
        "case_count": len(group_cases),
        "answer": answer,
        "error": error,
        "elapsed_seconds": round(elapsed, 1),
        "log_file": str(agent._log_rendered_path),
    }

    # Write each group's result to its own file
    safe_name = table_name.replace("/", "_")
    (out_dir / f"{safe_name}.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    log(f"[{group_id}] done, elapsed {elapsed:.1f}s -> {out_dir / (safe_name + '.json')}")
    return result


def run_update(args: argparse.Namespace, dev_path: str, cover_out: str, yaml_path: str) -> int:
    """Run grouped-by-table semantic update: one Agent session per table group."""
    from Agent.config_loader import build_mysql_config, load_config
    from Agent.tools import MySQLTool, register_all_tools
    from LLM import build_llm_config

    dev = Path(dev_path)
    if not dev.exists():
        print(f"Error: dev.json not found: {dev}", file=sys.stderr)
        return 1
    cover_path = Path(cover_out)
    if not cover_path.exists():
        print(f"Error: min_cover.json not found: {cover_path}", file=sys.stderr)
        return 1

    cases_map = _load_cases(dev)
    grouped = _load_grouped_by_table(cover_path)
    if not grouped:
        print(f"Error: no grouped_by_table in {cover_path}", file=sys.stderr)
        return 1

    # Build group tasks (skip cases missing from the dataset)
    group_tasks: list[tuple[str, list[dict[str, Any]]]] = []
    for table_name, cid_list in grouped.items():
        group_cases = []
        for cid in cid_list:
            case = cases_map.get(cid)
            if case is not None:
                group_cases.append({"case_id": cid, "case": case})
        if group_cases:
            group_tasks.append((table_name, group_cases))
    if not group_tasks:
        print("Error: no valid table groups found", file=sys.stderr)
        return 1

    ts = time.strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.update_out) if args.update_out else \
        PROJECT_ROOT / "scripts" / "output" / f"grouped_{args.dataset}_{ts}"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Config and tool registration (once per process)
    # LLM model/base_url/api_key come from the repo-root .env (see LLM/config.py)
    config_data = load_config(CONFIG_PATH)
    llm_config = build_llm_config(config_data)
    mysql_config = build_mysql_config(config_data)
    mysql_tool = MySQLTool(mysql_config)
    register_all_tools(mysql_tool)

    # Case counts: references = sum over groups (a case may appear in multiple
    # table groups); unique = distinct case IDs
    case_refs = sum(len(gc) for _, gc in group_tasks)
    unique_cases = len({ct["case_id"] for _, gc in group_tasks for ct in gc})
    semantic_file = args.semantic or Path(yaml_path).name
    log(f"Dataset: {args.dataset}  table groups: {len(group_tasks)}  "
        f"case refs: {case_refs} (unique cases: {unique_cases})")
    log(f"Output dir: {out_dir}")

    started = time.time()
    results: list[dict[str, Any]] = []

    # Run table groups serially
    for table_name, group_cases in group_tasks:
        results.append(_run_one_group(
            table_name, group_cases, args.prompt.strip(),
            llm_config, mysql_tool, args.agent, semantic_file,
            args.database, out_dir,
        ))

    # Summary
    elapsed = time.time() - started
    ok_count = sum(1 for r in results if not r.get("error"))
    summary = {
        "dataset": args.dataset,
        "agent": args.agent,
        "semantic_file": semantic_file,
        "prompt": args.prompt.strip(),
        "group_count": len(group_tasks),
        "case_refs": case_refs,
        "unique_cases": unique_cases,
        "success": ok_count,
        "failed": len(results) - ok_count,
        "elapsed_seconds": round(elapsed, 1),
        "results": sorted(results, key=lambda r: str(r.get("table", ""))),
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    log(f"\nAll done: success {ok_count}/{len(results)}, total elapsed {elapsed:.1f}s")
    log(f"Summary: {out_dir / 'summary.json'}")
    return 0


# ===========================================================================
# Stage 5: run (DataAgent batch over dev.json cases)
# ===========================================================================

def _parse_case_range(range_str: str, prefix: str) -> set[str]:
    """Parse '0-9,20-29' into {prefix}_{n} case IDs."""
    ids: set[str] = set()
    for seg in range_str.split(","):
        seg = seg.strip()
        if not seg:
            continue
        if "-" in seg:
            lo, hi = seg.split("-", 1)
            lo_i, hi_i = int(lo), int(hi)
            if lo_i > hi_i:
                lo_i, hi_i = hi_i, lo_i
            ids.update(f"{prefix}_{n}" for n in range(lo_i, hi_i + 1))
        else:
            ids.add(f"{prefix}_{int(seg)}")
    return ids


def _run_one_case(
    case_id: str,
    case: dict[str, Any],
    prompt_template: str,
    setting: int,
    llm_config: Any,
    mysql_tool: Any,
    agent_key: str,
    semantic_file: str,
    database: str,
    out_dir: Path,
    generated_dir: Path,
) -> dict[str, Any]:
    """Run one case (single Agent session), return the result summary."""
    from Agent.base import ReActAgent
    from Agent.common import set_current_context, set_current_mysql_tool
    from Agent.context import AgentContext
    from LLM import build_client_from_env

    question = case.get("question", "")
    started = time.time()
    session_id = f"run_{case_id}_{int(started)}"

    set_current_context(AgentContext(
        semantic_file=semantic_file,
        database=database,
        case_id=case_id,
        session_id=session_id,
        # submit_SQL writes directly to unified-output/.../generated/{case_id}.sql
        generated_dir=str(generated_dir),
    ))
    set_current_mysql_tool(mysql_tool)

    agent = ReActAgent(
        client=build_client_from_env(llm_config),
        llm_config=llm_config,
        agent_key=agent_key,
    )

    log(f"[{case_id}] start")
    error = ""
    answer = ""
    try:
        hints = _build_setting_hints(case, setting)
        prompt = prompt_template
        if "{question}" in prompt:
            prompt = prompt.replace("{question}", question)
        else:
            prompt = f"{prompt}\n\n## Question\n{question}"
        prompt = prompt.replace("{hints}", hints) if "{hints}" in prompt else f"{hints}{prompt}"
        answer = agent.run(prompt)
    except Exception as exc:  # noqa: BLE001
        error = str(exc)
        log(f"[{case_id}] error: {exc}")

    elapsed = time.time() - started
    result = {
        "case_id": case_id,
        "question": question,
        "setting": setting,
        "answer": answer,
        "error": error,
        "elapsed_seconds": round(elapsed, 1),
        "session_id": session_id,
        "log_file": str(agent._log_rendered_path),
    }
    (out_dir / f"{case_id}.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    log(f"[{case_id}] done, elapsed {elapsed:.1f}s")
    return result


def run_run(args: argparse.Namespace, dev_path: str) -> int:
    """Run DataAgent over dev.json cases; final SQL is submitted via submit_SQL.

    Output is written DIRECTLY in the BEAVER unified-output format:
        eval/unified-output/durian/{run_name}/generated/{case_id}.sql  (by submit_SQL)
        eval/unified-output/durian/{run_name}/gold/{case_id}.sql       (by this stage)
    Per-case session logs still go to --run-out (scripts/output/run_* by default).
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

    from Agent.config_loader import build_mysql_config, load_config
    from Agent.tools import MySQLTool, register_all_tools
    from LLM import build_llm_config

    dev = Path(dev_path)
    if not dev.exists():
        print(f"Error: dev.json not found: {dev}", file=sys.stderr)
        return 1
    cases_map = _load_cases(dev)
    if not cases_map:
        print(f"Error: no cases in {dev}", file=sys.stderr)
        return 1

    # Preserve dev.json order
    ordered_ids = [str(c.get("id", "")) for c in json.loads(dev.read_text(encoding="utf-8")) if c.get("id")]

    # Select cases: --cases ∪ --case-range, default all
    selected: set[str] = set()
    if args.cases.strip():
        selected.update(cid.strip() for cid in args.cases.split(",") if cid.strip())
    if args.case_range.strip():
        try:
            selected |= _parse_case_range(args.case_range, args.dataset)
        except ValueError:
            print(f"Error: invalid --case-range: {args.case_range}", file=sys.stderr)
            return 1
    case_ids = [cid for cid in ordered_ids if (cid in selected or not selected)]
    if not case_ids:
        print("Error: no matching cases found", file=sys.stderr)
        return 1

    # Database: explicit --database, else derived from dataset (dw_real → dw)
    database = args.database or ("dw" if args.dataset == "dw_real" else args.dataset)
    # Semantic YAML: explicit --semantic, else named after the database (Agent/semantic/{db}.yaml)
    semantic_file = args.semantic or f"{database}.yaml"
    prompt_template = args.run_prompt.strip() or DEFAULT_RUN_PROMPT

    config_data = load_config(CONFIG_PATH)
    # LLM model/base_url/api_key come from the repo-root .env (see LLM/config.py)
    llm_config = build_llm_config(config_data)
    mysql_config = build_mysql_config(config_data)
    mysql_tool = MySQLTool(mysql_config)
    register_all_tools(mysql_tool)

    # BEAVER unified-output directories (final evaluation format)
    ts = time.strftime("%Y%m%d-%H%M%S")
    run_name = args.run_name.strip() or \
        f"{llm_config.model}-beaver-{args.dataset}-setting{args.setting}-log-{ts}"
    unified_dir = PROJECT_ROOT.parent / "unified-output" / "durian" / run_name
    generated_dir = unified_dir / "generated"
    gold_dir = unified_dir / "gold"
    generated_dir.mkdir(parents=True, exist_ok=True)
    gold_dir.mkdir(parents=True, exist_ok=True)

    # Write gold SQL up-front so every selected case has a gold file
    for cid in case_ids:
        gold_sql = cases_map[cid].get("sql", "") or ""
        (gold_dir / f"{cid}.sql").write_text(gold_sql, encoding="utf-8")
        # Pre-create an empty prediction so cases where the agent never calls
        # submit_SQL are still scored (as wrong) by the official evaluator
        pred_path = generated_dir / f"{cid}.sql"
        if not pred_path.exists():
            pred_path.write_text("", encoding="utf-8")

    # Per-case session logs (answer/error/elapsed), separate from unified output
    out_dir = Path(args.run_out) if args.run_out else \
        PROJECT_ROOT / "scripts" / "output" / f"run_{args.dataset}_{ts}"
    out_dir.mkdir(parents=True, exist_ok=True)

    workers = max(1, args.run_workers)
    setting = args.setting
    log(f"Dataset: {args.dataset}  cases: {len(case_ids)}  agent: {args.run_agent}  "
        f"database: {database}  semantic: {semantic_file}  workers: {workers}  "
        f"model: {llm_config.model}  setting: {setting}")
    log(f"Unified output: {unified_dir}")
    log(f"Session logs:   {out_dir}")

    started = time.time()
    results: list[dict[str, Any]] = []

    if workers == 1:
        for cid in case_ids:
            results.append(_run_one_case(
                cid, cases_map[cid], prompt_template, setting,
                llm_config, mysql_tool, args.run_agent, semantic_file,
                database, out_dir, generated_dir,
            ))
    else:
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _run_one_case, cid, cases_map[cid], prompt_template, setting,
                    llm_config, mysql_tool, args.run_agent, semantic_file,
                    database, out_dir, generated_dir,
                ): cid for cid in case_ids
            }
            for fut in as_completed(futures):
                results.append(fut.result())

    elapsed = time.time() - started
    ok_count = sum(1 for r in results if not r.get("error"))
    submitted = sum(1 for cid in case_ids
                    if (generated_dir / f"{cid}.sql").read_text(encoding="utf-8").strip())
    summary = {
        "dataset": args.dataset,
        "agent": args.run_agent,
        "database": database,
        "semantic_file": semantic_file,
        "model": llm_config.model,
        "setting": setting,
        "case_count": len(case_ids),
        "case_ids": case_ids,
        "success": ok_count,
        "failed": len(results) - ok_count,
        "submitted": submitted,
        "unified_dir": str(unified_dir),
        "elapsed_seconds": round(elapsed, 1),
        "results": sorted(results, key=lambda r: str(r.get("case_id", ""))),
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    log(f"\nRun done: success {ok_count}/{len(results)}, submitted SQL {submitted}/{len(case_ids)}, "
        f"total elapsed {elapsed:.1f}s")
    log(f"Summary: {out_dir / 'summary.json'}")
    log(f"\nEvaluate with (from eval/):")
    log(f"  python evaluate_ex_acc.py --dataset {args.dataset} "
        f"--input_dir unified-output/durian/{run_name}")
    return 0


# ===========================================================================
# Main
# ===========================================================================

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # ── Global ──
    g_global = p.add_argument_group("global")
    g_global.add_argument("--stages", default="all",
                          help=f"stages to run (comma-separated: {','.join(ALL_STAGES)}; default all in order)")
    g_global.add_argument("--dataset", default="dw",
                          help="dataset name (for cover/update/run/eval, default dw)")
    g_global.add_argument("--database", default="",
                          help="MySQL database name (required for export/update; run derives it from dataset if omitted)")
    g_global.add_argument("--yaml", default=None,
                          help="semantic YAML path (default Agent/semantic/{database}.yaml)")
    g_global.add_argument("--dev", default=None,
                          help="dev.json path (default ../../data/{dataset}/dev.json in the BEAVER repo)")
    g_global.add_argument("--sampled", action="store_true",
                          help="use ../../data/{dataset}/dev_sampled.json instead of dev.json "
                               "(BEAVER evaluation subset)")
    g_global.add_argument("--dry-run", action="store_true",
                          help="export/vector stages count only, do not write")

    # ── Stage: export ──
    # (no dedicated options; uses --database/--yaml/--dry-run from global)

    # ── Stage: vector ──
    g_vector = p.add_argument_group("stage: vector (YAML → vector store)")
    g_vector.add_argument("--db-dir", default="Agent/zvec_db",
                          help="vector store root directory (default Agent/zvec_db)")
    g_vector.add_argument("--workers", type=int, default=100,
                          help="concurrent embedding threads (default 100)")

    # ── Stage: cover ──
    g_cover = p.add_argument_group("stage: cover (dev.json → min cover set)")
    g_cover.add_argument("--cover-out", default=None,
                         help="min_cover.json output path (default data/{dataset}/min_cover.json)")
    g_cover.add_argument("--cover-target", choices=["tables", "columns", "both"], default="both",
                         help="cover target (default both)")
    g_cover.add_argument("--dialect", default="mysql",
                         help="sqlglot dialect (default mysql)")
    g_cover.add_argument("--min-cases", type=int, default=1,
                         help="each table/column covered by at least N selected cases (default 1)")

    # ── Stage: update ──
    g_update = p.add_argument_group("stage: update (grouped-by-table semantic update)")
    g_update.add_argument("--prompt", default="",
                          help="task prompt (required; injected material fixed to question + sql)")
    g_update.add_argument("--agent", default="Semantic",
                          help="agent key (default Semantic)")
    g_update.add_argument("--semantic", default=None,
                          help="semantic YAML file name (default: file name of --yaml)")
    g_update.add_argument("--update-out", default=None,
                          help="result output directory (default scripts/output/grouped_{dataset}_{ts}/)")

    # ── Stage: run ──
    g_run = p.add_argument_group("stage: run (dev.json cases → DataAgent sessions)")
    g_run.add_argument("--setting", type=int, choices=[0, 1, 2], default=0,
                       help="BEAVER hint setting: 0=semantic network only (default), "
                            "1=+gold tables/column mapping/join keys, "
                            "2=+domain knowledge/subquery decomposition")
    g_run.add_argument("--run-prompt", default="",
                       help="task prompt template ({question}/{hints} placeholders; default built-in prompt)")
    g_run.add_argument("--run-agent", default="DataAgent",
                       help="agent key (default DataAgent)")
    g_run.add_argument("--cases", default="",
                       help="comma-separated case IDs to run (default all in dev.json)")
    g_run.add_argument("--case-range", default="",
                       help='case index range like "0-9,20-29" (union with --cases)')
    g_run.add_argument("--run-workers", type=int, default=1,
                       help="concurrent Agent sessions (default 1, serial)")
    g_run.add_argument("--run-out", default=None,
                       help="session log directory (default scripts/output/run_{dataset}_{ts}/)")
    g_run.add_argument("--run-name", default="",
                       help="run name for eval/unified-output/durian/{run_name}/ "
                            "(default {model}-beaver-{dataset}-setting{setting}-log-{ts})")

    args = p.parse_args(argv)

    # Resolve stages to run
    if args.stages.strip().lower() == "all":
        stages = list(ALL_STAGES)
    else:
        stages = [s.strip() for s in args.stages.split(",") if s.strip()]
        invalid = [s for s in stages if s not in ALL_STAGES]
        if invalid:
            print(f"Error: unknown stages {invalid}, valid: {','.join(ALL_STAGES)} or all", file=sys.stderr)
            return 1
        # Run in fixed order (same as ALL_STAGES), ignoring the user's ordering
        stages = [s for s in ALL_STAGES if s in stages]

    # Argument validation (per stage requirements; no defaults/fallbacks)
    if any(s in stages for s in ("export", "update")) and not args.database:
        print("Error: --database is required for export/update stages", file=sys.stderr)
        return 1
    if "update" in stages and not args.prompt.strip():
        print("Error: --prompt is required for the update stage", file=sys.stderr)
        return 1

    # Derived paths
    yaml_path = _resolve(args.yaml or f"Agent/semantic/{args.database or 'default'}.yaml")
    if args.dev:
        dev_path = _resolve(args.dev)
    else:
        # Default to the shared BEAVER dataset directory (repo_root/data/{dataset}/)
        dev_file = "dev_sampled.json" if args.sampled else "dev.json"
        dev_path = str(BEAVER_DATA / args.dataset / dev_file)
    cover_out = _resolve(args.cover_out or f"data/{args.dataset}/min_cover.json")

    print("=" * 70)
    print(f"Pipeline: {' → '.join(stages)}")
    print(f"  database : {args.database or '(not set)'}")
    print(f"  dataset  : {args.dataset}")
    print(f"  yaml     : {yaml_path}")
    print(f"  dev.json : {dev_path}")
    print(f"  cover    : {cover_out}")
    print("=" * 70)

    # Run stages in order
    total_started = time.time()
    for idx, stage in enumerate(stages, 1):
        print(f"\n[{idx}/{len(stages)}] ▶ {stage}: {STAGE_DESC[stage]}")
        print("-" * 70)
        t0 = time.time()
        try:
            if stage == "export":
                rc = run_export(args, yaml_path)
            elif stage == "vector":
                rc = run_vector(args, yaml_path)
            elif stage == "cover":
                rc = run_cover(args, dev_path, cover_out)
            elif stage == "update":
                rc = run_update(args, dev_path, cover_out, yaml_path)
            elif stage == "run":
                rc = run_run(args, dev_path)
            else:
                rc = 1
        except Exception as exc:  # noqa: BLE001
            print(f"[{stage}] exception: {exc}", file=sys.stderr)
            rc = 1
        elapsed = time.time() - t0
        if rc != 0:
            print(f"\n✗ Stage {stage} failed (exit code {rc}, elapsed {elapsed:.1f}s), pipeline aborted.",
                  file=sys.stderr)
            return rc
        print(f"✓ Stage {stage} done (elapsed {elapsed:.1f}s)")

    print("\n" + "=" * 70)
    print(f"Pipeline finished: {' → '.join(stages)} (total elapsed {time.time() - total_started:.1f}s)")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
