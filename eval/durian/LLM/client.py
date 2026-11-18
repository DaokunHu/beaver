"""OpenAI-compatible client construction.

api_key / base_url both come from the .env at the repo root (passed in via LLMConfig);
process environment variables are no longer read.
"""

from __future__ import annotations

from openai import OpenAI

from LLM.config import LLMConfig


def build_client_from_env(llm_config: LLMConfig) -> OpenAI:
    """Build an OpenAI client from LLMConfig (sourced from .env)."""
    if not llm_config.api_key:
        raise ValueError("Missing LLM_API_KEY in the repo-root .env file")
    if not llm_config.base_url:
        raise ValueError("Missing LLM_BASE_URL in the repo-root .env file")
    return OpenAI(api_key=llm_config.api_key, base_url=llm_config.base_url)
