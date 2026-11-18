#!/usr/bin/env python
"""Agent CLI conversation entry point: input -> ReAct loop -> output (supports multi-turn dialogue).

Usage (from the project root):
    python -m Agent.cli --database dw [--agent DataAgent] [--semantic Beaver.yaml]
                        [--once "question"]

Notes:
- --database is required: the MySQL database name, no default value.
- Multi-turn dialogue: REPL loop; the full context of the previous turn is automatically carried into the next.
- Exit: type exit / quit, or press Ctrl-C / Ctrl-D.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

# Allow running directly as a script (python Agent/cli.py)
_PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from Agent.base import ReActAgent
from Agent.common import set_current_context
from Agent.config_loader import (
    build_mysql_config,
    load_config,
)
from Agent.context import AgentContext
from Agent.tools import MySQLTool, register_all_tools
from LLM import build_client_from_env, build_llm_config

AGENT_DIR = Path(__file__).resolve().parent
CONFIG_PATH = AGENT_DIR / "react_config.json"


class CLIAgent(ReActAgent):
    """Agent that prints the ReAct process to the terminal."""

    def on_step_start(self, step: int) -> None:
        print(f"\n\033[90m── step {step} ──\033[0m", flush=True)

    def on_reasoning(self, content: str) -> None:
        if content:
            print(f"\033[90m[thinking] {content}\033[0m", flush=True)

    def on_final_answer(self, step: int, answer: str) -> None:
        print(f"\n\033[92m[answer]\033[0m {answer}", flush=True)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--agent", default="DataAgent", help="agent key in agents.json")
    p.add_argument("--semantic", default="", help="semantic YAML file name (under Agent/semantic/)")
    p.add_argument("--database", required=True,
                   help="MySQL database name (required, no default)")
    p.add_argument("--once", default=None, help="run this question once and exit (non-interactive)")
    args = p.parse_args(argv)

    # 1. Configuration and tool registration (LLM/MySQL/embedding all come from the repo-root .env)
    config_data = load_config(CONFIG_PATH)
    llm_config = build_llm_config(config_data)
    mysql_config = build_mysql_config(config_data)
    register_all_tools(MySQLTool(mysql_config))

    # 2. Inject the runtime context (database is explicitly given via --database; tools read it from the context at execution time)
    set_current_context(AgentContext(
        semantic_file=args.semantic,
        database=args.database,
        case_id=args.once[:30] if args.once else "cli",
        session_id="cli",
    ))

    # 3. Build the Agent
    agent = CLIAgent(
        client=build_client_from_env(llm_config),
        llm_config=llm_config,
        agent_key=args.agent,
    )

    # 4. Single-shot mode
    if args.once:
        agent.run(args.once)
        return 0

    # 5. REPL multi-turn dialogue: each round carries the full context of the previous round
    print(f"Agent CLI ({agent.agent_name})")
    print("Type a question to start; exit / quit to leave.\n")
    msgs: list[dict[str, Any]] | None = None
    while True:
        try:
            text = input("\033[94myou> \033[0m").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nBye.")
            return 0
        if not text:
            continue
        if text.lower() in ("exit", "quit"):
            print("Bye.")
            return 0
        try:
            agent.run(text, msgs, append_user=True)
        except Exception as exc:  # noqa: BLE001
            print(f"\033[91m[error] {exc}\033[0m", flush=True)
        msgs = list(getattr(agent, "_final_msgs", None) or (msgs or []))


if __name__ == "__main__":
    raise SystemExit(main())
