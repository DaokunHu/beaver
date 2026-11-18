"""Configuration loading module.

Loads non-sensitive semantic network configuration from react_config.json;
MySQL connection info (host/port/user/password) and the embedding endpoint/keys
all come from the .env file at the repo root (process environment variables are not read).
For LLM configuration, use the LLM package directly (build_llm_config).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from env_config import get_env, require_env

from Agent.tools import (
	DEFAULT_ENTITY_REQUIRED_FIELDS,
	MySQLConfig,
	SemanticNetworkConfig,
)

__all__ = [
	"load_config",
	"build_mysql_config",
	"build_semantic_config",
]


def load_config(config_path: Path) -> dict[str, Any]:
	"""Load the full configuration (raw JSON dict).

	Secrets and endpoints (LLM/embedding keys, MySQL credentials) are read
	exclusively from the repo-root .env file (see env_config).
	"""
	return json.loads(config_path.read_text(encoding="utf-8"))


def build_mysql_config(config_data: dict[str, Any]) -> MySQLConfig:
	"""Build MySQLConfig from the repo-root .env.

	host/port/user/password all come from .env (MYSQL_HOST/MYSQL_PORT/MYSQL_USER/MYSQL_PASSWORD).
	database is not part of the config: it must be explicitly provided by the caller
	(session/batch task/script argument) and set after construction via
	dataclasses.replace(mysql_config, database=...).
	"""
	mysql_data = config_data.get("mysql", {})
	return MySQLConfig(
		host=get_env("MYSQL_HOST", "localhost"),
		port=int(get_env("MYSQL_PORT", "3306")),
		user=get_env("MYSQL_USER", "root"),
		password=require_env("MYSQL_PASSWORD"),
		database="",
		max_rows_returned=int(mysql_data.get("max_rows_returned", 500000)),
		connect_timeout_seconds=int(mysql_data.get("connect_timeout_seconds", 60)),
	)


def build_semantic_config(config_data: dict[str, Any]) -> SemanticNetworkConfig:
	"""Build SemanticNetworkConfig from the config dict.

	yaml_path is optional: used if configured, otherwise left empty (the actual path is
	assembled at call time by _resolve_semantic_tool in tools.py from semantic_dir + file).
	"""
	semantic_data = config_data.get("semantic_network", {})
	raw_yaml_path = semantic_data.get("yaml_path", "")
	semantic_dir = str(semantic_data.get("semantic_dir", ""))

	# Configured entries override the defaults per entity type; types absent from the
	# config keep their DEFAULT_ENTITY_REQUIRED_FIELDS requirements.
	configured_fields = semantic_data.get("entity_required_fields", {})
	if not isinstance(configured_fields, dict):
		raise ValueError("semantic_network.entity_required_fields must be an object")
	for etype, required_fields in configured_fields.items():
		if not isinstance(etype, str):
			raise ValueError("entity_required_fields keys must be strings")
		if not isinstance(required_fields, list) or any(not isinstance(fn, str) for fn in required_fields):
			raise ValueError("entity_required_fields values must be lists of strings")

	merged_fields = dict(DEFAULT_ENTITY_REQUIRED_FIELDS)
	merged_fields.update(configured_fields)

	return SemanticNetworkConfig(
		yaml_path=str(raw_yaml_path) if raw_yaml_path else "",
		entity_required_fields={
			str(k).lower(): [str(v).strip() for v in required_values if str(v).strip()]
			for k, required_values in merged_fields.items()
		},
		semantic_dir=semantic_dir,
		neighbors_max_depth=int(semantic_data.get("neighbors_max_depth", 2)),
		vector_db_dir=str(semantic_data.get("vector_db_dir", "")),
		# Embedding endpoint/model come from the repo-root .env file
		embedding_base_url=get_env("EMBEDDING_BASE_URL"),
		embedding_model=get_env("EMBEDDING_MODEL", "qwen3.7-text-embedding"),
		embedding_dim=int(semantic_data.get("embedding_dim", 1024)),
		vector_topk=int(semantic_data.get("vector_topk", 10)),
	)
