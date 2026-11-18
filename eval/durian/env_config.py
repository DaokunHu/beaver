"""Configuration loader for the BEAVER repo-root `.env` file.

All secrets and endpoint settings (LLM / embedding / MySQL) are read
EXCLUSIVELY from the repo-root `.env` file — process environment variables
are NOT consulted.

Expected keys in `<repo_root>/.env` (see the committed `<repo_root>/.env.example`
template for the full list; values below are placeholders):

    # Durian LLM (any OpenAI-compatible endpoint)
    LLM_API_KEY=<your-llm-api-key>
    LLM_MODEL=<your-llm-model>
    LLM_BASE_URL=<your-llm-base-url>

    # Durian embedding (vector store build / semantic search)
    EMBEDDING_API_KEY=<your-embedding-api-key>
    EMBEDDING_MODEL=<your-embedding-model>
    EMBEDDING_BASE_URL=<your-embedding-base-url>

    # MySQL (shared with the other BEAVER methods)
    MYSQL_HOST=localhost
    MYSQL_PORT=3306
    MYSQL_USER=root
    MYSQL_PASSWORD=<your-mysql-password>
"""

from __future__ import annotations

from pathlib import Path

DURIAN_ROOT = Path(__file__).resolve().parent
# eval/durian -> eval -> BEAVER repo root
BEAVER_ROOT = DURIAN_ROOT.parent.parent
ENV_PATH = BEAVER_ROOT / ".env"

_cache: dict[str, str] | None = None


def _load() -> dict[str, str]:
    """Parse the repo-root .env file once and cache the result."""
    global _cache
    if _cache is None:
        values: dict[str, str] = {}
        if ENV_PATH.exists():
            for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):].strip()
                if "=" not in line:
                    continue
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip().strip('"').strip("'")
        _cache = values
    return _cache


def get_env(key: str, default: str = "") -> str:
    """Read a value from the repo-root .env file (no process-env fallback)."""
    return _load().get(key, default)


def require_env(key: str) -> str:
    """Read a required value from the repo-root .env file; raise if missing."""
    value = get_env(key)
    if not value:
        raise ValueError(f"Missing '{key}' in {ENV_PATH}")
    return value
