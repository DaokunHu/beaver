"""LLM configuration dataclasses and builder functions.

model / base_url / api_key all come from the .env file at the repo root
(LLM_MODEL / LLM_BASE_URL / LLM_API_KEY); react_config.json and process
environment variables are no longer read for them.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from env_config import require_env


@dataclass
class LLMConfig:
    """LLM invocation parameters."""

    model: str
    base_url: str
    api_key: str
    reasoning_effort: str
    enable_thinking: bool
    clear_thinking: bool
    temperature: float
    max_steps: int


def build_llm_config(config_data: dict[str, Any]) -> LLMConfig:
    """Build LLMConfig: model/base_url/api_key come from .env, the rest from react_config.json.

    config_data is the content of react_config.json and only provides ReAct loop
    parameters (temperature / max_steps / reasoning, etc.).
    """
    return LLMConfig(
        model=require_env("LLM_MODEL"),
        base_url=require_env("LLM_BASE_URL"),
        api_key=require_env("LLM_API_KEY"),
        reasoning_effort=str(config_data.get("reasoning_effort", "medium")),
        clear_thinking=bool(config_data.get("clear_thinking", True)),
        enable_thinking=bool(config_data.get("enable_thinking", True)),
        temperature=float(config_data.get("temperature", 0)),
        max_steps=int(config_data.get("max_steps", 1000)),
    )
