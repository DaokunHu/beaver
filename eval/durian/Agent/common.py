"""Common module: shared infrastructure that breaks circular dependencies.

Includes:
- ContextVar definitions (context, mysql_tool)
- Tool registry (register_tool, get_tool_handler, build_tools_schema)
- agents.json config management (load_agents_config with caching)
- Prompt file management
- Argument parsing helpers
"""

from __future__ import annotations

import json
from contextvars import ContextVar
from pathlib import Path
from typing import Any, Callable

from Agent.context import AgentContext

# ──────────────────────────────────────────────
# Path constants
# ──────────────────────────────────────────────

AGENT_DIR = Path(__file__).resolve().parent
PROMPTS_DIR = AGENT_DIR / "prompts"
AGENTS_CONFIG_FILE = PROMPTS_DIR / "agents.json"
LOGS_DIR = AGENT_DIR / "logs"


def build_llm_log_path(session_id: str = "") -> Path:
    """Build the LLM log file path (Agent/logs/llm_{ts}_{session_id}_rendered.log).

    Logs are managed by the Agent layer itself; upper layers (Web/CLI) only need to
    provide a naming identifier via AgentContext.session_id; "default" is used when absent.
    """
    import time

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    safe_id = (session_id or "default").strip() or "default"
    return LOGS_DIR / f"llm_{ts}_{safe_id}_rendered.log"

# ──────────────────────────────────────────────
# ContextVar definitions (globally shared; eliminates the base.py <-> tools.py circular dependency)
# ──────────────────────────────────────────────

_current_context: ContextVar[AgentContext | None] = ContextVar("_current_context", default=None)
_current_mysql_tool: ContextVar[Any] = ContextVar("_current_mysql_tool", default=None)

# ──────────────────────────────────────────────
# Argument parsing helpers (eliminate 15+ duplicated boilerplate sites)
# ──────────────────────────────────────────────


def parse_tool_args(raw_arguments: str) -> tuple[dict[str, Any], dict[str, Any] | None]:
    """Parse the tool arguments JSON string.

    Returns:
        (args, error) — error is None on success; otherwise it is an error response dict.
    """
    try:
        return json.loads(raw_arguments or "{}"), None
    except json.JSONDecodeError:
        return {}, {"ok": False, "error": "Invalid JSON arguments"}


# ──────────────────────────────────────────────
# agents.json config management (with mtime caching)
# ──────────────────────────────────────────────

_agents_cache: tuple[float, dict[str, dict[str, Any]]] | None = None


def load_agents_config() -> dict[str, dict[str, Any]]:
    """Load the agents.json config (cached by file mtime to avoid reading the file on every call)."""
    global _agents_cache
    if not AGENTS_CONFIG_FILE.exists():
        return {}
    mtime = AGENTS_CONFIG_FILE.stat().st_mtime
    if _agents_cache and _agents_cache[0] == mtime:
        return _agents_cache[1]
    try:
        with open(AGENTS_CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return {}
    _agents_cache = (mtime, data)
    return data


def load_prompt(name: str) -> str:
    """Load a Markdown template file from the prompts directory."""
    path = PROMPTS_DIR / name
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


# ──────────────────────────────────────────────
# Tool registry
# ──────────────────────────────────────────────

_TOOL_REGISTRY: dict[str, dict[str, Any]] = {}


def register_tool(name: str, schema: dict[str, Any], handler: Callable[..., dict[str, Any]]) -> None:
    """Register a tool in the global registry."""
    _TOOL_REGISTRY[name] = {"schema": schema, "handler": handler}


def get_tool_handler(name: str) -> Callable[..., dict[str, Any]] | None:
    """Get the handler function of a registered tool."""
    entry = _TOOL_REGISTRY.get(name)
    return entry["handler"] if entry else None


def build_tools_schema(tool_names: list[str]) -> list[dict[str, Any]]:
    """Build a TOOLS_SCHEMA subset from a list of tool names."""
    return [
        _TOOL_REGISTRY[name]["schema"]
        for name in tool_names
        if name in _TOOL_REGISTRY
    ]


def build_agent_tools(agent_key: str) -> list[dict[str, Any]]:
    """Build the Agent's tool set from the tool names configured in agents.json."""
    config = load_agents_config()
    agent_cfg = config.get(agent_key, {})
    return build_tools_schema(agent_cfg.get("tools", []))


# ──────────────────────────────────────────────
# ContextVar accessors (used by tools.py)
# ──────────────────────────────────────────────


def get_current_context() -> AgentContext | None:
    """Return the current runtime context (AgentContext); None when there is no context."""
    return _current_context.get()


def set_current_context(ctx: AgentContext | None) -> None:
    """Set the current runtime context."""
    _current_context.set(ctx)


def get_current_mysql_tool() -> Any:
    return _current_mysql_tool.get()


def set_current_mysql_tool(tool: Any) -> None:
    _current_mysql_tool.set(tool)
