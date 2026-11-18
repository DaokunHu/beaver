"""LLM foundation layer: pure LLM invocation capabilities, zero business dependencies.

Includes:
- LLMConfig: LLM invocation parameter configuration
- build_client_from_env: build an OpenAI-compatible client from environment config
- safe_json_loads: JSON repair and safe parsing for LLM output
- stream_chat_completion: streaming chat completion core

Dependency direction: Web -> Agent -> LLM (strictly one-way; this package must not import Agent/Web).
"""

from LLM.client import build_client_from_env
from LLM.config import LLMConfig, build_llm_config
from LLM.json_repair import safe_json_loads
from LLM.stream import stream_chat_completion

__all__ = [
    "LLMConfig",
    "build_llm_config",
    "build_client_from_env",
    "safe_json_loads",
    "stream_chat_completion",
]
