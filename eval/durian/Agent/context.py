"""Agent runtime context: the single bridge between the Agent core layer and upper layers (Web/CLI/scripts).

The Agent core is unaware of the "session" concept; it only obtains via AgentContext:
- semantic_file: current semantic YAML file name
- case_id / session_id: log identifiers (optional)

Upper layers (CLI, pipeline scripts) are responsible for constructing and injecting
the context; without one (direct script calls), tools execute with default behavior.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class AgentContext:
    """Agent runtime context (pure data, zero upper-layer dependencies)."""

    semantic_file: str = ""
    database: str = ""
    case_id: str = ""
    session_id: str = ""
    # BEAVER unified-output generated/ directory: when set, submit_SQL writes directly to
    # {generated_dir}/{case_id}.sql (official evaluation format), bypassing intermediate layers
    generated_dir: str = ""
