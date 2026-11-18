"""FastAPI backend service (minimal version): read semantic network YAML -> render the semantic network graph.

Start (from the project root): python -m Web.server or uvicorn Web.server:app
Visit: http://localhost:8000/
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import FastAPI
from fastapi.responses import HTMLResponse

from Agent.config_loader import (
    build_semantic_config,
    load_config,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
AGENT_DIR = PROJECT_ROOT / "Agent"
WEB_DIR = Path(__file__).resolve().parent
CONFIG_PATH = AGENT_DIR / "react_config.json"
GRAPH_HTML = WEB_DIR / "graph.html"

app = FastAPI(title="Durian Semantic Graph Server")


def _semantic_base_dir() -> Path:
    """Directory containing semantic YAML files (configured semantic_dir takes priority, otherwise Agent/semantic/)."""
    semantic_config = build_semantic_config(load_config(CONFIG_PATH))
    semantic_dir = semantic_config.semantic_dir
    if semantic_dir:
        base_dir = Path(semantic_dir).expanduser()
        if not base_dir.is_absolute():
            base_dir = (PROJECT_ROOT / base_dir).resolve()
        return base_dir
    return AGENT_DIR / "semantic"


@app.get("/", response_class=HTMLResponse)
async def graph_page() -> HTMLResponse:
    return HTMLResponse(GRAPH_HTML.read_text(encoding="utf-8"))


@app.get("/api/semantic/yamls")
async def list_semantic_yamls() -> dict[str, Any]:
    base_dir = _semantic_base_dir()
    files: list[dict[str, str]] = []
    if base_dir.exists():
        for item in sorted(base_dir.iterdir()):
            if item.is_file() and item.suffix in (".yaml", ".yml"):
                files.append({"file": item.name, "label": item.name})
    return {"files": files}


@app.get("/api/semantic/graph")
async def get_semantic_graph(yaml: str = "") -> dict[str, Any]:
    """Read the specified YAML (the first one by default) and return {nodes, edges} for graph rendering."""
    from Agent.tools import SemanticNetworkTool

    semantic_config = build_semantic_config(load_config(CONFIG_PATH))

    base_dir = _semantic_base_dir()
    if yaml:
        file_path = (base_dir / yaml).resolve()
        # Prevent directory traversal: must be inside base_dir
        if not str(file_path).startswith(str(base_dir.resolve())):
            return {"nodes": [], "edges": [], "error": "invalid yaml path"}
    else:
        candidates = sorted(p for p in base_dir.iterdir() if p.suffix in (".yaml", ".yml")) if base_dir.exists() else []
        if not candidates:
            return {"nodes": [], "edges": [], "error": f"no yaml found in {base_dir}"}
        file_path = candidates[0]
    semantic_config.yaml_path = str(file_path)

    tool = SemanticNetworkTool(semantic_config)
    doc = tool._load()

    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []

    for table in doc.get("tables", []):
        table_id = str(table.get("id", ""))
        if not table_id:
            continue
        node = {
            "id": table_id,
            "label": str(table.get("name", table_id)),
            "nodeType": "table",
            "desc": str(table.get("desc", "")),
        }
        if table.get("columns"):
            node["columns"] = table.get("columns")
        nodes.append(node)

    for metric in doc.get("metrics", []) or []:
        metric_id = str(metric.get("id", ""))
        if not metric_id:
            continue
        nodes.append({
            "id": metric_id,
            "label": str(metric.get("name", metric_id)),
            "nodeType": "metric",
            "desc": str(metric.get("desc", "")),
            "category": str(metric.get("category", "")),
            "sql": str(metric.get("sql", "")),
        })

    for concept in doc.get("concepts", []) or []:
        concept_id = str(concept.get("id", ""))
        if not concept_id:
            continue
        nodes.append({
            "id": concept_id,
            "label": str(concept.get("name", concept_id)),
            "nodeType": "concept",
            "desc": str(concept.get("desc", "")),
            "tables": concept.get("tables", []),
            "comparisons": concept.get("comparisons", []),
            "decision_guide": concept.get("decision_guide", {}),
        })

    for concept in doc.get("column_concepts", []) or []:
        concept_id = str(concept.get("id", ""))
        if not concept_id:
            continue
        nodes.append({
            "id": concept_id,
            "label": str(concept.get("name", concept_id)),
            "nodeType": "column_concept",
            "desc": str(concept.get("desc", "")),
            "columns": concept.get("columns", []),
            "comparisons": concept.get("comparisons", []),
            "decision_guide": concept.get("decision_guide", {}),
        })

    for rel in doc.get("relationships", []) or []:
        src_id = str(rel.get("source_entity_id", ""))
        tgt_id = str(rel.get("target_entity_id", ""))
        if not src_id or not tgt_id:
            continue
        edge = {
            "source": src_id,
            "target": tgt_id,
            "edgeType": str(rel.get("relation_type", "")),
            "desc": str(rel.get("desc", "")),
        }
        if rel.get("columns"):
            edge["columns"] = rel.get("columns")
        edges.append(edge)

    return {"nodes": nodes, "edges": edges}


if __name__ == "__main__":
    import uvicorn

    # Must be run from the project root: python -m Web.server
    uvicorn.run("Web.server:app", host="0.0.0.0", port=8000, reload=False)
