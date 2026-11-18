"""Tool classes, configuration dataclasses, and tool registration.

Includes:
- MySQLConfig / MySQLTool
- SemanticNetworkConfig / SemanticNetworkTool
- Default constants
- Tool schema registration (register_all_tools)
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import mysql.connector
import yaml

from Agent.common import (
    get_current_context,
    parse_tool_args,
    register_tool,
    set_current_mysql_tool,
)


# ──────────────────────────────────────────────
# Default constants
# ──────────────────────────────────────────────

DEFAULT_ENTITY_REQUIRED_FIELDS: dict[str, list[str]] = {
	"table": ["id", "name", "desc"],
	"metric": ["id", "name", "sql", "desc", "category"],
	"concept": ["id", "name", "desc"],
	"column_concept": ["id", "name", "desc"],
}


# ──────────────────────────────────────────────
# Configuration dataclasses
# ──────────────────────────────────────────────


@dataclass
class MySQLConfig:
	host: str
	port: int
	user: str
	password: str
	database: str
	max_rows_returned: int
	connect_timeout_seconds: int


@dataclass
class SemanticNetworkConfig:
	yaml_path: str
	entity_required_fields: dict[str, list[str]]
	semantic_dir: str = ""
	neighbors_max_depth: int = 2           # semantic_graph(query_neighbors) max traversal depth
	# Zvec vector store config (each YAML corresponds to an independent subdirectory, further split by entity_type into collections)
	vector_db_dir: str = ""                # Vector store root directory (relative to project root or absolute path)
	embedding_base_url: str = ""          # Vector embedding service URL (OpenAI-compatible endpoint)
	embedding_model: str = "qwen3.7-text-embedding"  # Vector embedding model
	embedding_dim: int = 1024              # Vector dimension (must match model output)
	vector_topk: int = 10                  # Default topk for vector retrieval


# ──────────────────────────────────────────────
# MySQL Tool
# ──────────────────────────────────────────────


class MySQLTool:
	def __init__(self, config: MySQLConfig) -> None:
		self.config = config

	@staticmethod
	def _drain_remaining_rows(cursor: Any, batch_size: int = 1000) -> bool:
		"""Drain remaining rows; return True if any rows were discarded."""
		discarded = False
		while True:
			remaining = cursor.fetchmany(batch_size)
			if not remaining:
				break
			discarded = True
		return discarded

	@staticmethod
	def _rows_to_text(rows: list[dict[str, Any]]) -> str:
		"""Format query result rows into a Markdown table text.

		All values are uniformly converted to string via str() to avoid
		JSON serialization errors from date/datetime/Decimal types.
		"""
		if not rows:
			return "(no data)"
		headers = list(rows[0].keys())
		lines = ["| " + " | ".join(headers) + " |"]
		lines.append("| " + " | ".join("---" for _ in headers) + " |")
		for row in rows:
			cells = [str(row.get(h, "")) for h in headers]
			lines.append("| " + " | ".join(cells) + " |")
		return "\n".join(lines)

	def execute_query(self, sql: str) -> dict[str, Any]:
		conn = None
		cursor = None
		# database is read from the runtime context first (specified per session/script); falls back to the config value
		ctx = get_current_context()
		database = (ctx.database if ctx and ctx.database else "") or self.config.database
		if not database:
			return {"ok": False, "error": "No database specified: please provide it explicitly via session/script arguments"}
		try:
			conn = mysql.connector.connect(
				host=self.config.host,
				port=self.config.port,
				user=self.config.user,
				password=self.config.password,
				database=database,
				connection_timeout=self.config.connect_timeout_seconds,
			)
			cursor = conn.cursor(dictionary=True)
			cursor.execute(sql)

			if cursor.with_rows:
				rows = cursor.fetchmany(self.config.max_rows_returned)
				truncated = self._drain_remaining_rows(cursor)
				while cursor.nextset():
					if cursor.with_rows:
						self._drain_remaining_rows(cursor)
				text = self._rows_to_text(rows)
				if truncated:
					text += (
						f"\n\n(Result truncated: showing only the first {len(rows)} rows, "
						f"exceeding max_rows_returned={self.config.max_rows_returned}. "
						"Use aggregation/LIMIT in your SQL to narrow the result if needed.)"
					)
				return {
					"ok": True,
					"type": "rows",
					"row_count": len(rows),
					"truncated": truncated,
					"text": text,
				}

			conn.commit()
			return {
				"ok": True,
				"type": "mutation",
				"affected_rows": cursor.rowcount,
			}
		except Exception as exc:
			return {
				"ok": False,
				"error": str(exc),
			}
		finally:
			if cursor is not None:
				try:
					cursor.close()
				except mysql.connector.Error:
					pass
			if conn is not None and conn.is_connected():
				conn.close()


# ──────────────────────────────────────────────
# Semantic Network Tool
# ──────────────────────────────────────────────


class SemanticNetworkTool:
	def __init__(self, config: SemanticNetworkConfig) -> None:
		self.config = config
		self._vector_store = None

	@staticmethod
	def _supported_entity_types() -> list[str]:
		return ["table", "metric", "concept", "column_concept"]

	@staticmethod
	def _sanitize_namespace(name: str) -> str:
		"""Sanitize a YAML name into a directory name, avoiding path injection and illegal characters."""
		text = (name or "default").strip()
		if not text:
			return "default"
		text = text.replace("\\", "_").replace("/", "_")
		return text

	def _vector_db_dir_for_yaml(self) -> str | None:
		"""Return the independent vector store directory for the current YAML.

		Rule: base_dir / yaml_stem, ensuring each semantic network has its own set of collections.
		"""
		if not self.config.vector_db_dir:
			return None
		base_dir = Path(self.config.vector_db_dir).expanduser()
		if not self.config.yaml_path:
			return str(base_dir)
		yaml_path = Path(self.config.yaml_path).expanduser()
		namespace = self._sanitize_namespace(yaml_path.stem)
		return str((base_dir / namespace).resolve())

	def _get_vector_store(self):
		"""Lazily load the vector store (only when config is enabled), isolated by YAML directory."""
		vector_db_dir = self._vector_db_dir_for_yaml()
		if self._vector_store is None and vector_db_dir:
			from Agent.zvec_store import SemanticVectorStore
			self._vector_store = SemanticVectorStore(
				db_dir=vector_db_dir,
				base_url=self.config.embedding_base_url,
				model=self.config.embedding_model,
				dimension=self.config.embedding_dim,
				topk=self.config.vector_topk,
			)
		return self._vector_store

	def _sync_vector(self, entity_type: str, entity: dict[str, Any]) -> None:
		"""After entity add/update, sync its vector to the vector store (idempotent, failure does not block the main flow)."""
		store = self._get_vector_store()
		if store is None:
			return
		try:
			synonyms_raw = entity.get("synonyms", [])
			synonyms = [str(s) for s in synonyms_raw if s] if isinstance(synonyms_raw, list) else []
			store.upsert_entity(
				etype=entity_type.lower(),
				entity_id=str(entity.get("id", "")),
				name=str(entity.get("name", "")),
				desc=str(entity.get("desc", "")),
				synonyms=synonyms,
			)
		except Exception as exc:
			print(f"[Warning] Vector sync failed ({entity_type}/{entity.get('id')}): {exc}")

	def _yaml_path(self) -> Path:
		return Path(self.config.yaml_path).expanduser().resolve()

	@staticmethod
	def _ensure_collections(doc: dict[str, Any]) -> None:
		doc.setdefault("tables", [])
		doc.setdefault("relationships", [])
		doc.setdefault("metrics", [])
		doc.setdefault("concepts", [])
		doc.setdefault("column_concepts", [])

	def _load(self) -> dict[str, Any]:
		path = self._yaml_path()
		if not path.exists():
			doc: dict[str, Any] = {
				"version": 1,
				"database": "",
				"tables": [],
				"relationships": [],
				"metrics": [],
				"concepts": [],
				"column_concepts": [],
			}
			return doc

		try:
			with path.open("r", encoding="utf-8") as f:
				loaded = yaml.safe_load(f)
		except Exception:
			loaded = {}
		if loaded is None:
			loaded = {}
		if not isinstance(loaded, dict):
			raise ValueError("Semantic network YAML root node must be an object")
		self._ensure_collections(loaded)
		return loaded

	def _save(self, doc: dict[str, Any]) -> None:
		path = self._yaml_path()
		path.parent.mkdir(parents=True, exist_ok=True)
		with path.open("w", encoding="utf-8") as f:
			yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False)

	@staticmethod
	def _find_by_id(items: list[dict[str, Any]], item_id: str) -> dict[str, Any] | None:
		for item in items:
			if not isinstance(item, dict):
				continue
			if str(item.get("id", "")) == item_id:
				return item
		return None

	def _find_table(self, doc: dict[str, Any], table_id: str) -> dict[str, Any] | None:
		tables = doc.get("tables", [])
		if not isinstance(tables, list):
			return None
		for table in tables:
			if not isinstance(table, dict):
				continue
			if str(table.get("id", "")) == table_id:
				return table
		return None

	def _entity_exists(self, doc: dict[str, Any], entity_type: str, entity_id: str) -> bool:
		etype = entity_type.lower()
		collection_key = self._collection_key(etype)
		items = doc.get(collection_key, [])
		if not isinstance(items, list):
			return False
		return self._find_by_id(items, entity_id) is not None

	@staticmethod
	def _collection_key(entity_type: str) -> str:
		mapping = {
			"table": "tables",
			"relationship": "relationships",
			"metric": "metrics",
			"concept": "concepts",
			"column_concept": "column_concepts",
		}
		key = mapping.get(entity_type.lower())
		if not key:
			raise ValueError(f"Unsupported entity_type: {entity_type}")
		return key

	def _validate_entity_payload(self, entity_type: str, entity: dict[str, Any]) -> str | None:
		etype = entity_type.lower()
		if etype not in self._supported_entity_types():
			return f"Unsupported entity_type: {entity_type}"
		required_fields = self.config.entity_required_fields.get(etype, ["id"])
		for field_name in required_fields:
			if str(entity.get(field_name, "")).strip() == "":
				return f"entity.{field_name} is required for entity_type={etype}"
		return None

	def _validate_concept_tables(self, doc: dict[str, Any], entity: dict[str, Any]) -> str | None:
		"""Validate that tables referenced in concept.tables already exist."""
		tables = entity.get("tables", [])
		if tables is None:
			return None
		if not isinstance(tables, list):
			return "concept.tables must be an array"
		for table_id in tables:
			tid = str(table_id).strip()
			if not tid:
				return "concept.tables must not contain empty table IDs"
			if not self._entity_exists(doc, "table", tid):
				return f"concept.tables references a non-existent table: {tid}"
		return None

	def _validate_column_concept_columns(self, doc: dict[str, Any], entity: dict[str, Any]) -> str | None:
		"""Validate that columns referenced in column_concept.columns already exist.

		columns format is a string array, each element is "table_id.column_name".
		"""
		columns = entity.get("columns", [])
		if columns is None:
			return None
		if not isinstance(columns, list):
			return "column_concept.columns must be an array"
		for col_ref in columns:
			ref = str(col_ref).strip()
			if not ref:
				return "column_concept.columns must not contain empty column references"
			parts = ref.rsplit(".", 1)
			if len(parts) != 2 or not parts[0] or not parts[1]:
				return f"column_concept.columns reference format error (should be table_id.column_name): {ref}"
			table_id, col_name = parts
			table = self._find_table(doc, table_id)
			if table is None:
				return f"column_concept.columns references a non-existent table: {table_id}"
			table_columns = table.get("columns", {})
			if not isinstance(table_columns, dict) or col_name not in table_columns:
				return f"column_concept.columns references a non-existent column: {ref}"
		return None

	def add_entity(self, entity_type: str, entity: dict[str, Any]) -> dict[str, Any]:
		validation_error = self._validate_entity_payload(entity_type=entity_type, entity=entity)
		if validation_error is not None:
			return {"ok": False, "error": validation_error}

		entity_id = str(entity.get("id", "")) .strip()
		if not entity_id:
			return {"ok": False, "error": "entity.id is required"}

		doc = self._load()
		self._ensure_collections(doc)

		etype = entity_type.lower()
		if etype == "concept":
			validation_error = self._validate_concept_tables(doc, entity)
			if validation_error is not None:
				return {"ok": False, "error": validation_error}
		if etype == "column_concept":
			validation_error = self._validate_column_concept_columns(doc, entity)
			if validation_error is not None:
				return {"ok": False, "error": validation_error}
		collection_key = self._collection_key(etype)
		collection = doc.get(collection_key, [])
		if not isinstance(collection, list):
			return {"ok": False, "error": f"{collection_key} must be a list"}
		if self._find_by_id(collection, entity_id) is not None:
			return {"ok": False, "error": f"{etype} id already exists: {entity_id}"}

		collection.append(entity)
		self._save(doc)
		# Sync vector store
		self._sync_vector(etype, entity)
		return {
			"ok": True,
			"type": etype,
			"id": entity_id,
		}

	@staticmethod
	def _deep_update(target: dict[str, Any], updates: dict[str, Any]) -> dict[str, Any]:
		"""Deep merge update: recursively merge updates into target.

		- For dict values, merge recursively (not replace wholesale)
		- For scalar values, overwrite directly
		"""
		for key, new_val in updates.items():
			if key not in target:
				target[key] = new_val
				continue
			old_val = target[key]
			if isinstance(old_val, dict) and isinstance(new_val, dict):
				SemanticNetworkTool._deep_update(old_val, new_val)
			else:
				target[key] = new_val
		return target

	def update_entity(self, entity_type: str, entity_id: str, updates: dict[str, Any]) -> dict[str, Any]:
		"""Update an existing entity in the semantic network.

		updates is a dict, where key is a dot-separated field path and value is the new value.
		Each key-value is located and updated independently without affecting each other. For example:
		- {"desc": "new description"} → update the desc field
		- {"columns.TERM_CODE.desc": "term code"} → update the desc of TERM_CODE column in columns
		- {"desc": "new description", "columns.TERM_CODE.desc": "term code"} → update both fields simultaneously
		- {"columns": {"COL1": {"desc": "new description"}}} → deep merge update columns dict

		columns is in dict format: key is column name, value is a {desc, default?} object.
		"""
		etype = entity_type.lower()
		if etype not in self._supported_entity_types():
			return {"ok": False, "error": f"Unsupported entity_type: {entity_type}"}

		eid = str(entity_id).strip()
		if not eid:
			return {"ok": False, "error": "entity_id is required"}

		if not isinstance(updates, dict) or len(updates) == 0:
			return {"ok": False, "error": "updates must be a non-empty object, key is field path, value is new value"}

		doc = self._load()
		self._ensure_collections(doc)

		collection_key = self._collection_key(etype)
		collection = doc.get(collection_key, [])
		if not isinstance(collection, list):
			return {"ok": False, "error": f"{collection_key} must be a list"}
		existing = self._find_by_id(collection, eid)
		if existing is None:
			return {"ok": False, "error": f"{etype} not found: {eid}"}

		# Apply updates per path: expand "a.b.c" → value into nested dict then deep merge
		for path, value in updates.items():
			parts = path.split(".")
			nested: dict[str, Any] = {}
			current = nested
			for i, part in enumerate(parts):
				if i == len(parts) - 1:
					current[part] = value
				else:
					current[part] = {}
					current = current[part]
			self._deep_update(existing, nested)

		if etype == "concept":
			validation_error = self._validate_concept_tables(doc, existing)
			if validation_error is not None:
				return {"ok": False, "error": validation_error}
		if etype == "column_concept":
			validation_error = self._validate_column_concept_columns(doc, existing)
			if validation_error is not None:
				return {"ok": False, "error": validation_error}

		self._save(doc)
		# Sync vector store
		self._sync_vector(etype, existing)
		return {
			"ok": True,
			"type": etype,
			"id": eid,
		}

	def _delete_vector(self, entity_type: str, entity_id: str) -> None:
		"""After entity deletion, sync deletion of its vector from the vector store (idempotent, failure does not block the main flow)."""
		store = self._get_vector_store()
		if store is None:
			return
		try:
			store.delete_entity(etype=entity_type.lower(), entity_id=str(entity_id))
		except Exception as exc:
			print(f"[Warning] Vector deletion failed ({entity_type}/{entity_id}): {exc}")

	def delete_entity(self, entity_type: str, entity_id: str) -> dict[str, Any]:
		"""Delete an entity from the semantic network, and sync cleanup of vector store and associated relationships."""
		etype = entity_type.lower()
		eid = str(entity_id).strip()
		if not eid:
			return {"ok": False, "error": "entity_id is required"}
		if etype not in self._supported_entity_types():
			return {"ok": False, "error": f"Unsupported entity_type: {entity_type}"}

		doc = self._load()
		self._ensure_collections(doc)

		collection_key = self._collection_key(etype)
		collection = doc.get(collection_key, [])
		if not isinstance(collection, list):
			return {"ok": False, "error": f"{collection_key} must be a list"}
		existing = self._find_by_id(collection, eid)
		if existing is None:
			return {"ok": False, "error": f"{etype} not found: {eid}"}
		collection.remove(existing)
		self._save(doc)
		self._delete_vector(etype, eid)
		self._cleanup_relationships(doc, etype, eid)
		# table type: remove this table reference from all concept.tables and column_concept.columns arrays
		if etype == "table":
			self._cleanup_concept_table_refs(doc, eid)
			self._cleanup_column_concept_refs(doc, eid)
		return {
			"ok": True,
			"type": etype,
			"id": eid,
		}

	def _cleanup_relationships(self, doc: dict[str, Any], entity_type: str, entity_id: str) -> None:
		"""Delete all relationship edges associated with the specified entity (source or target match)."""
		relationships = doc.get("relationships", [])
		if not isinstance(relationships, list):
			return
		etype_lower = entity_type.lower()
		eid = str(entity_id)
		original_len = len(relationships)
		relationships[:] = [
			rel for rel in relationships
			if isinstance(rel, dict)
			and not (
				(str(rel.get("source_entity_type", "")).lower() == etype_lower
				 and str(rel.get("source_entity_id", "")) == eid)
				or
				(str(rel.get("target_entity_type", "")).lower() == etype_lower
				 and str(rel.get("target_entity_id", "")) == eid)
			)
		]
		if len(relationships) < original_len:
			self._save(doc)

	def _cleanup_concept_table_refs(self, doc: dict[str, Any], table_id: str) -> None:
		"""When deleting a table, remove its reference from all concept.tables arrays."""
		concepts = doc.get("concepts", [])
		if not isinstance(concepts, list):
			return
		tid = str(table_id)
		changed = False
		for concept in concepts:
			if not isinstance(concept, dict):
				continue
			tables = concept.get("tables", [])
			if not isinstance(tables, list):
				continue
			new_tables = [t for t in tables if str(t) != tid]
			if len(new_tables) != len(tables):
				concept["tables"] = new_tables
				changed = True
		if changed:
			self._save(doc)

	def _cleanup_column_concept_refs(self, doc: dict[str, Any], table_id: str) -> None:
		"""When deleting a table, remove its column references from all column_concept.columns arrays.

		columns elements are in the format "table_id.column_name", removed by table_id prefix match.
		"""
		column_concepts = doc.get("column_concepts", [])
		if not isinstance(column_concepts, list):
			return
		tid = str(table_id)
		prefix = f"{tid}."
		changed = False
		for concept in column_concepts:
			if not isinstance(concept, dict):
				continue
			columns = concept.get("columns", [])
			if not isinstance(columns, list):
				continue
			new_columns = [c for c in columns if not str(c).startswith(prefix)]
			if len(new_columns) != len(columns):
				concept["columns"] = new_columns
				changed = True
		if changed:
			self._save(doc)

	def _validate_join_relationship(
		self,
		doc: dict[str, Any],
		source_entity_type: str,
		source_entity_id: str,
		target_entity_type: str,
		target_entity_id: str,
		relation_type: str,
		columns: Any,
	) -> str | None:
		"""Validate the endpoints and column pairs of a joins relationship."""
		if relation_type != "joins":
			return f"Unsupported relation_type: {relation_type}. Allowed type: joins"
		if source_entity_type.lower() != "table":
			return "joins source_entity_type must be table"
		if target_entity_type.lower() != "table":
			return "joins target_entity_type must be table"
		if not self._entity_exists(doc, "table", source_entity_id):
			return f"Source entity not found: table/{source_entity_id}"
		if not self._entity_exists(doc, "table", target_entity_id):
			return f"Target entity not found: table/{target_entity_id}"
		if not isinstance(columns, list) or not columns:
			return "joins.columns must be a non-empty array of column pairs"

		source_table = self._find_table(doc, source_entity_id)
		target_table = self._find_table(doc, target_entity_id)
		source_columns = source_table.get("columns", {}) if source_table else {}
		target_columns = target_table.get("columns", {}) if target_table else {}
		if not isinstance(source_columns, dict) or not isinstance(target_columns, dict):
			return "columns of both tables in joins must be objects"
		for pair in columns:
			if not isinstance(pair, dict):
				return "Each element of joins.columns must be an object"
			source_column = str(pair.get("source_column", "")).strip()
			target_column = str(pair.get("target_column", "")).strip()
			if not source_column or not target_column:
				return "Each element of joins.columns must contain source_column and target_column"
			if source_column not in source_columns:
				return f"Source table does not have column: {source_entity_id}.{source_column}"
			if target_column not in target_columns:
				return f"Target table does not have column: {target_entity_id}.{target_column}"
		return None

	def add_relationship(
		self,
		relationship_id: str,
		source_entity_type: str,
		source_entity_id: str,
		target_entity_type: str,
		target_entity_id: str,
		relation_type: str,
		desc: str,
		columns: list[dict[str, str]] | None = None,
	) -> dict[str, Any]:
		doc = self._load()
		self._ensure_collections(doc)
		relationships = doc.get("relationships", [])
		if not isinstance(relationships, list):
			return {"ok": False, "error": "relationships must be a list"}
		if self._find_by_id(relationships, relationship_id) is not None:
			return {"ok": False, "error": f"Relationship id already exists: {relationship_id}"}

		validation_error = self._validate_join_relationship(
			doc,
			source_entity_type,
			source_entity_id,
			target_entity_type,
			target_entity_id,
			relation_type,
			columns,
		)
		if validation_error is not None:
			return {"ok": False, "error": validation_error}

		# joins relationship is a table-to-table relationship, columns field records the joinable column pairs
		# columns format: [{"source_column": "...", "target_column": "..."}, ...]
		relationship = {
			"id": relationship_id,
			"source_entity_type": source_entity_type,
			"source_entity_id": source_entity_id,
			"target_entity_type": target_entity_type,
			"target_entity_id": target_entity_id,
			"relation_type": relation_type,
			"desc": desc,
		}
		relationship["columns"] = columns
		relationships.append(relationship)
		self._save(doc)
		return {
			"ok": True,
			"type": "relationship",
			"id": relationship_id,
		}

	def update_relationship(
		self,
		relationship_id: str,
		updates: dict[str, Any],
	) -> dict[str, Any]:
		"""Update an existing relationship in the semantic network.

		Fields in updates are merged onto the existing relationship (shallow merge: same-name fields overwrite, new fields appended).
		If updates contains source_entity_type/source_entity_id/target_entity_type/
		target_entity_id/relation_type, their validity will be re-validated.
		"""
		rid = str(relationship_id).strip()
		if not rid:
			return {"ok": False, "error": "relationship_id is required"}

		doc = self._load()
		self._ensure_collections(doc)
		relationships = doc.get("relationships", [])
		if not isinstance(relationships, list):
			return {"ok": False, "error": "relationships must be a list"}

		existing = self._find_by_id(relationships, rid)
		if existing is None:
			return {"ok": False, "error": f"Relationship not found: {rid}"}

		# Validate the updated fields for legality
		new_source_type = str(updates.get("source_entity_type", existing.get("source_entity_type", ""))).strip()
		new_source_id = str(updates.get("source_entity_id", existing.get("source_entity_id", ""))).strip()
		new_target_type = str(updates.get("target_entity_type", existing.get("target_entity_type", ""))).strip()
		new_target_id = str(updates.get("target_entity_id", existing.get("target_entity_id", ""))).strip()
		new_relation_type = str(updates.get("relation_type", existing.get("relation_type", ""))).strip()

		new_columns = updates.get("columns", existing.get("columns"))
		validation_error = self._validate_join_relationship(
			doc,
			new_source_type,
			new_source_id,
			new_target_type,
			new_target_id,
			new_relation_type,
			new_columns,
		)
		if validation_error is not None:
			return {"ok": False, "error": validation_error}

		# Shallow merge update
		existing.update(updates)
		# Ensure key field types are consistent
		existing["source_entity_type"] = new_source_type
		existing["source_entity_id"] = new_source_id
		existing["target_entity_type"] = new_target_type
		existing["target_entity_id"] = new_target_id
		existing["relation_type"] = new_relation_type
		self._save(doc)
		return {
			"ok": True,
			"type": "relationship",
			"id": rid,
		}

	def delete_relationship(self, relationship_id: str) -> dict[str, Any]:
		"""Delete a relationship edge from the semantic network."""
		rid = str(relationship_id).strip()
		if not rid:
			return {"ok": False, "error": "relationship_id is required"}

		doc = self._load()
		self._ensure_collections(doc)
		relationships = doc.get("relationships", [])
		if not isinstance(relationships, list):
			return {"ok": False, "error": "relationships must be a list"}

		existing = self._find_by_id(relationships, rid)
		if existing is None:
			return {"ok": False, "error": f"Relationship not found: {rid}"}
		relationships.remove(existing)
		self._save(doc)
		return {
			"ok": True,
			"type": "relationship",
			"id": rid,
		}

	# ──────────────────────────────────────────
	# Query methods (search / get_entity / query_neighbors / trace_lineage)
	# ──────────────────────────────────────────

	def _iter_all_entities(self, doc: dict[str, Any]):
		"""Iterate over all entities, yield (entity_type, entity_dict)."""
		for table in doc.get("tables", []):
			if not isinstance(table, dict):
				continue
			yield "table", table
		for etype in ("metric", "concept", "column_concept"):
			collection_key = self._collection_key(etype)
			items = doc.get(collection_key, [])
			if not isinstance(items, list):
				continue
			for item in items:
				if not isinstance(item, dict):
					continue
				yield etype, item

	def list_entities(
		self,
		type: str | None = None,
		page: int = 1,
		page_size: int = 20,
	) -> dict[str, Any]:
		"""List entities or relationships with pagination support.

		Args:
		    type: Optional filter. Supported values:
		        - Entity types: table, metric, concept, column_concept
		        - Relationship types: join (alias for joins relationships)
		        - relationship (all relationships)
		        When omitted, all entity types are listed in order: table, metric, concept, column_concept.
		page: 1-based page number.
		page_size: Number of items per page.

		Returns:
		    dict with: ok, type, page, page_size, total, total_pages, has_next, items.
		    For entity types, each item is: {id, name, desc, entity_type}.
		    For relationships, each item is: {id, source_entity_id, target_entity_id, relation_type, desc}.
		"""
		doc = self._load()
		self._ensure_collections(doc)

		# Normalize type
		normalized = (type or "").lower().strip() or None

		# Map aliases
		if normalized == "join":
			normalized = "joins"

		# Relationship listing
		if normalized in ("joins", "relationship", "relationships"):
			relationships = doc.get("relationships", [])
			if not isinstance(relationships, list):
				relationships = []
			all_items: list[dict[str, Any]] = []
			for rel in relationships:
				if not isinstance(rel, dict):
					continue
				# Filter by relation_type when type=joins
				rel_type = str(rel.get("relation_type", ""))
				if normalized == "joins" and rel_type != "joins":
					continue
				all_items.append({
					"id": str(rel.get("id", "")),
					"source_entity_id": str(rel.get("source_entity_id", "")),
					"target_entity_id": str(rel.get("target_entity_id", "")),
					"relation_type": rel_type,
					"desc": str(rel.get("desc", "")),
				})
			total = len(all_items)
			total_pages = (total + page_size - 1) // page_size if page_size > 0 else 0
			if total_pages == 0:
				total_pages = 1
			if page < 1:
				page = 1
			if page > total_pages:
				page = total_pages
			start = (page - 1) * page_size
			end = start + page_size
			page_items = all_items[start:end]
			return {
				"ok": True,
				"type": normalized,
				"page": page,
				"page_size": page_size,
				"total": total,
				"total_pages": total_pages,
				"has_next": page < total_pages,
				"items": page_items,
			}

		# Entity listing
		if normalized:
			if normalized not in self._supported_entity_types():
				return {"ok": False, "error": f"Unsupported type: {type}"}
			etype_list = [normalized]
		else:
			etype_list = ["table", "metric", "concept", "column_concept"]

		all_items: list[dict[str, Any]] = []
		for et in etype_list:
			collection_key = self._collection_key(et)
			items = doc.get(collection_key, [])
			if not isinstance(items, list):
				continue
			for item in items:
				if not isinstance(item, dict):
					continue
				all_items.append({
					"id": str(item.get("id", "")),
					"name": str(item.get("name", "")),
					"desc": str(item.get("desc", "")),
					"entity_type": et,
				})

		total = len(all_items)
		total_pages = (total + page_size - 1) // page_size if page_size > 0 else 0
		if total_pages == 0:
			total_pages = 1

		if page < 1:
			page = 1
		if page > total_pages:
			page = total_pages

		start = (page - 1) * page_size
		end = start + page_size
		page_items = all_items[start:end]

		return {
			"ok": True,
			"type": normalized or "all",
			"page": page,
			"page_size": page_size,
			"total": total,
			"total_pages": total_pages,
			"has_next": page < total_pages,
			"items": page_items,
		}

	def semantic_get_entity(self, entity_id: str) -> dict[str, Any]:
		"""Get the full definition of a single entity by ID (searches across all types)."""
		doc = self._load()
		self._ensure_collections(doc)
		eid = entity_id.strip()

		for etype in self._supported_entity_types():
			collection_key = self._collection_key(etype)
			items = doc.get(collection_key, [])
			if not isinstance(items, list):
				continue
			entity = self._find_by_id(items, eid)
			if entity is not None:
				return {"ok": True, "entity": entity}

		return {"ok": False, "error": f"Entity not found: {eid}"}

	def semantic_get_entities(self, entity_ids: list[str]) -> dict[str, Any]:
		"""Get the full definitions of multiple entities by IDs (single document load).

		Returns:
			{"ok": True, "entities": [...], "not_found": [...]} — entities keep the same order
			as the input IDs; IDs that were not found are collected into not_found without
			interrupting retrieval of the other entities.
		"""
		doc = self._load()
		self._ensure_collections(doc)

		entities: list[dict[str, Any]] = []
		not_found: list[str] = []
		for raw_id in entity_ids:
			eid = str(raw_id).strip()
			if not eid:
				continue
			found = None
			for etype in self._supported_entity_types():
				collection_key = self._collection_key(etype)
				items = doc.get(collection_key, [])
				if not isinstance(items, list):
					continue
				entity = self._find_by_id(items, eid)
				if entity is not None:
					found = entity
					break
			if found is not None:
				entities.append(found)
			else:
				not_found.append(eid)

		if not entities and not_found:
			return {"ok": False, "error": f"Entities not found: {', '.join(not_found)}"}
		return {"ok": True, "entities": entities, "not_found": not_found}

	def _find_concepts_by_table(self, doc: dict[str, Any], table_id: str) -> list[dict[str, Any]]:
		"""Reverse lookup of all concepts containing the specified table_id (via concept.tables array soft reference).

		Returns a list of concept summaries: [{id, name, desc}].
		"""
		concepts = doc.get("concepts", [])
		if not isinstance(concepts, list):
			return []
		tid = str(table_id)
		result: list[dict[str, Any]] = []
		for concept in concepts:
			if not isinstance(concept, dict):
				continue
			tables = concept.get("tables", [])
			if not isinstance(tables, list):
				continue
			if tid in [str(t) for t in tables]:
				result.append({
					"id": str(concept.get("id", "")),
					"name": str(concept.get("name", "")),
					"desc": str(concept.get("desc", "")),
				})
		return result

	def _find_column_concepts_by_table(self, doc: dict[str, Any], table_id: str) -> list[dict[str, Any]]:
		"""Reverse lookup of all column_concepts containing the specified table_id (via column_concept.columns array soft reference).

		columns elements are in the format "table_id.column_name", matched by table_id prefix.
		Returns a list of column_concept summaries: [{id, name, desc}].
		"""
		column_concepts = doc.get("column_concepts", [])
		if not isinstance(column_concepts, list):
			return []
		tid = str(table_id)
		prefix = f"{tid}."
		result: list[dict[str, Any]] = []
		for concept in column_concepts:
			if not isinstance(concept, dict):
				continue
			columns = concept.get("columns", [])
			if not isinstance(columns, list):
				continue
			for c in columns:
				if str(c).startswith(prefix):
					result.append({
						"id": str(concept.get("id", "")),
						"name": str(concept.get("name", "")),
						"desc": str(concept.get("desc", "")),
					})
					break
		return result

	def _find_tables_by_concept(self, doc: dict[str, Any], concept_id: str) -> list[dict[str, Any]]:
		"""Return a list of table summaries referenced by concept.tables."""
		concept = self._get_entity_full(doc, "concept", concept_id)
		if concept is None:
			return []
		tables = concept.get("tables", [])
		if not isinstance(tables, list):
			return []
		result: list[dict[str, Any]] = []
		for table_id in tables:
			tid = str(table_id).strip()
			if not tid:
				continue
			table = self._get_entity_summary(doc, "table", tid)
			if table is not None:
				result.append(table)
		return result

	def _find_columns_by_column_concept(self, doc: dict[str, Any], concept_id: str) -> list[dict[str, Any]]:
		"""Return a list of column summaries referenced by column_concept.columns.

		columns elements are in the format "table_id.column_name", returns column summaries: [{entity_type, id, name, desc}].
		"""
		concept = self._get_entity_full(doc, "column_concept", concept_id)
		if concept is None:
			return []
		columns = concept.get("columns", [])
		if not isinstance(columns, list):
			return []
		result: list[dict[str, Any]] = []
		for ref in columns:
			ref_str = str(ref).strip()
			if not ref_str:
				continue
			parts = ref_str.rsplit(".", 1)
			if len(parts) != 2:
				continue
			table_id, col_name = parts
			table = self._find_table(doc, table_id)
			if table is None:
				continue
			table_columns = table.get("columns", {})
			if isinstance(table_columns, dict) and col_name in table_columns:
				col_info = table_columns[col_name]
				result.append({
					"entity_type": "column",
					"id": ref_str,
					"name": col_name,
					"desc": str(col_info.get("desc", "")) if isinstance(col_info, dict) else "",
				})
		return result

	def _get_entity_summary(self, doc: dict[str, Any], etype: str, eid: str) -> dict[str, Any] | None:
		"""Get entity summary (id, name, desc, entity_type)."""
		collection_key = self._collection_key(etype)
		items = doc.get(collection_key, [])
		if not isinstance(items, list):
			return None
		entity = self._find_by_id(items, eid)
		if entity is None:
			return None
		return {
			"entity_type": etype,
			"id": eid,
			"name": str(entity.get("name", "")),
			"desc": str(entity.get("desc", "")),
		}

	def _get_entity_full(self, doc: dict[str, Any], etype: str, eid: str) -> dict[str, Any] | None:
		"""Get the full definition of an entity from the loaded doc."""
		etype_lower = etype.lower()
		collection_key = self._collection_key(etype_lower)
		items = doc.get(collection_key, [])
		if not isinstance(items, list):
			return None
		return self._find_by_id(items, eid)

	def semantic_query_neighbors(
		self,
		entity_type: str,
		entity_id: str,
		direction: str = "both",
		relation_type: str | None = None,
		depth: int = 1,
	) -> dict[str, Any]:
		"""Query the relationship neighbors of an entity (graph traversal)."""
		doc = self._load()
		self._ensure_collections(doc)
		relationships = doc.get("relationships", [])
		if not isinstance(relationships, list):
			return {"ok": False, "error": "relationships must be a list"}

		etype = entity_type.lower()
		eid = entity_id.strip()
		if depth < 1:
			depth = 1
		max_depth = self.config.neighbors_max_depth
		if depth > max_depth:
			depth = max_depth

		visited: set[str] = set()
		results: list[dict[str, Any]] = []

		def _traverse(src_type: str, src_id: str, current_depth: int) -> None:
			if current_depth > depth:
				return
			key = f"{src_type}:{src_id}"
			if key in visited:
				return
			visited.add(key)

			for rel in relationships:
				if not isinstance(rel, dict):
					continue
				rel_rt = str(rel.get("relation_type", ""))
				rel_desc = str(rel.get("desc", ""))

				# Outgoing edge: source == entity
				if direction in ("outgoing", "both"):
					if (
						str(rel.get("source_entity_type", "")).lower() == src_type
						and str(rel.get("source_entity_id", "")) == src_id
					):
						if relation_type and rel_rt != relation_type:
							continue
						tgt_type = str(rel.get("target_entity_type", "")).lower()
						tgt_id = str(rel.get("target_entity_id", ""))
						target = self._get_entity_summary(doc, tgt_type, tgt_id)
						if target:
							results.append({
								"relation_type": rel_rt,
								"direction": "outgoing",
								"desc": rel_desc,
								**target,
							})
							if current_depth < depth:
								_traverse(tgt_type, tgt_id, current_depth + 1)

				# Incoming edge: target == entity
				if direction in ("incoming", "both"):
					if (
						str(rel.get("target_entity_type", "")).lower() == src_type
						and str(rel.get("target_entity_id", "")) == src_id
					):
						if relation_type and rel_rt != relation_type:
							continue
						src_t = str(rel.get("source_entity_type", "")).lower()
						src_i = str(rel.get("source_entity_id", ""))
						source = self._get_entity_summary(doc, src_t, src_i)
						if source:
							results.append({
								"relation_type": rel_rt,
								"direction": "incoming",
								"desc": rel_desc,
								**source,
							})
							if current_depth < depth:
								_traverse(src_t, src_i, current_depth + 1)

			# Soft reference adjacency: table reverse lookup for concept (table level) and column_concept (column level).
			if src_type == "table" and direction in ("incoming", "both"):
				if not relation_type or relation_type == "concept":
					for concept in self._find_concepts_by_table(doc, src_id):
						results.append({
							"relation_type": "concept",
							"direction": "incoming",
							"desc": "Associated with this table via concept.tables soft reference",
							"entity_type": "concept",
							"id": str(concept.get("id", "")),
							"name": str(concept.get("name", "")),
							"desc": str(concept.get("desc", "")),
						})
						if current_depth < depth:
							_traverse("concept", str(concept.get("id", "")), current_depth + 1)
				if not relation_type or relation_type == "column_concept":
					for concept in self._find_column_concepts_by_table(doc, src_id):
						results.append({
							"relation_type": "column_concept",
							"direction": "incoming",
							"desc": "Associated with this table via column_concept.columns soft reference",
							"entity_type": "column_concept",
							"id": str(concept.get("id", "")),
							"name": str(concept.get("name", "")),
							"desc": str(concept.get("desc", "")),
						})
						if current_depth < depth:
							_traverse("column_concept", str(concept.get("id", "")), current_depth + 1)

			# concept forward expands tables; column_concept forward expands columns.
			if src_type == "concept" and direction in ("outgoing", "both"):
				if not relation_type or relation_type == "concept":
					for table in self._find_tables_by_concept(doc, src_id):
						results.append({
							"relation_type": "concept",
							"direction": "outgoing",
							"desc": "Associated with business concept via concept.tables soft reference",
							**table,
						})
						if current_depth < depth:
							_traverse("table", str(table.get("id", "")), current_depth + 1)

			if src_type == "column_concept" and direction in ("outgoing", "both"):
				if not relation_type or relation_type == "column_concept":
					for column in self._find_columns_by_column_concept(doc, src_id):
						results.append({
							"relation_type": "column_concept",
							"direction": "outgoing",
							"desc": "Associated with column via column_concept.columns soft reference",
							**column,
						})
						if current_depth < depth:
							_traverse("column", str(column.get("id", "")), current_depth + 1)

		_traverse(etype, eid, 1)
		return {"ok": True, "count": len(results), "items": results}

	def semantic_query_metrics_by_table(self, table_id: str) -> dict[str, Any]:
		"""Reverse lookup of metrics that depend on a given table.

		Searches the table name directly in metric SQL to find all metrics referencing that table.
		"""
		doc = self._load()
		self._ensure_collections(doc)
		metrics = doc.get("metrics", [])
		if not isinstance(metrics, list):
			return {"ok": False, "error": "metrics must be a list"}

		tid = table_id.strip()
		if not tid:
			return {"ok": False, "error": "table_id is required"}
		# Validate table exists
		table = self._find_table(doc, tid)
		if table is None:
			return {"ok": False, "error": f"Table not found: {tid}"}

		# Search for table name directly in metric SQL
		results: list[dict[str, Any]] = []
		for m in metrics:
			if not isinstance(m, dict):
				continue
			sql = str(m.get("sql", ""))
			if not sql:
				continue
			if tid in sql:
				results.append({
					"metric_id": str(m.get("id", "")),
					"name": str(m.get("name", "")),
					"category": str(m.get("category", "")),
					"desc": str(m.get("desc", "")),
				})
		return {
			"ok": True,
			"table_id": tid,
			"table_name": str(table.get("name", "")),
			"count": len(results),
			"items": results,
		}

	def semantic_trace_lineage(self, metric_id: str) -> dict[str, Any]:
		"""Trace the complete lineage of a metric: parse dependent tables from the metric SQL."""
		doc = self._load()
		self._ensure_collections(doc)
		metrics = doc.get("metrics", [])
		if not isinstance(metrics, list):
			return {"ok": False, "error": "metrics must be a list"}

		metric_map: dict[str, dict[str, Any]] = {}
		for m in metrics:
			if isinstance(m, dict):
				metric_map[str(m.get("id", ""))] = m

		mid = metric_id.strip()
		if mid not in metric_map:
			return {"ok": False, "error": f"Metric not found: {mid}"}

		metric = metric_map[mid]
		sql = str(metric.get("sql", ""))

		# Match all known table IDs from SQL
		tables = doc.get("tables", [])
		if not isinstance(tables, list):
			tables = []
		children: list[dict[str, Any]] = []
		for table in tables:
			if not isinstance(table, dict):
				continue
			tid = str(table.get("id", ""))
			if tid and tid in sql:
				children.append({
					"entity_type": "table",
					"id": tid,
					"name": str(table.get("name", "")),
				})

		tree: dict[str, Any] = {
			"metric_id": mid,
			"name": str(metric.get("name", "")),
			"category": str(metric.get("category", "")),
			"sql": sql,
			"children": children,
		}
		return {"ok": True, "lineage": tree}


# ──────────────────────────────────────────────
# Tool Schema Definitions
# ──────────────────────────────────────────────


def _mysql_query_schema() -> dict[str, Any]:
	return {
		"type": "function",
		"function": {
			"name": "mysql_query",
			"description": "Execute SQL on the configured MySQL database (database is selected per session/task) and return results. No need to explicitly specify the database name in SQL; just use table names directly.",
			"parameters": {
				"type": "object",
				"properties": {
					"sql": {
						"type": "string",
						"description": "A valid SQL statement to execute.",
					}
				},
				"required": ["sql"],
			},
		},
	}


# ──────────────────────────────────────────────
# Tool Schema Definitions (6 semantic tools + mysql_query/submit_SQL)
# ──────────────────────────────────────────────


def _semantic_search_schema() -> dict[str, Any]:
	"""semantic_search: vector semantic retrieval (core entry tool)."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_search",
			"description": (
				"Perform semantic similarity retrieval in the semantic network vector store, searching for table, metric, concept, or column_concept entities.\n"
				"When entity_type is provided, only that type is searched; when omitted, all types are searched by default, each returning an independent topk.\n"
				"Returns results grouped by type (items_by_type), each entity only returns id and desc; full details are obtained via semantic_get.\n"
				"- table search: does not return column-level info or concept.\n"
				"- metric search: does not return sql, category.\n"
				"- concept search: does not return tables/comparisons/decision_guide.\n"
				"\n"
				"Usage strategy:\n"
				"- Candidates with score > 0.8 should be prioritized\n"
				"- 0.5-0.8 need verification via semantic_get\n"
				"- < 0.5 are usually not relevant\n"
				"\n"
				"Applicable scenario: when the user describes their needs in natural language, but keywords cannot precisely match table/metric names."
			),
			"parameters": {
				"type": "object",
				"properties": {
					"query": {
						"type": "string",
						"description": "Natural language query description, e.g. 'student course selection records', 'department cost summary'.",
					},
					"entity_type": {
						"type": "string",
						"description": "Entity type to search. When omitted, all entity types are searched by default, each returning an independent topk.",
						"enum": ["table", "metric", "concept", "column_concept"],
					},
					"topk": {
						"type": "integer",
						"description": "Number of results to return, default 10.",
						"minimum": 1,
						"maximum": 50,
					},
				},
				"required": ["query"],
			},
		},
	}


def _semantic_get_schema() -> dict[str, Any]:
	"""semantic_get: get entity details by ID (single or multiple)."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_get",
			"description": (
				"Get the full definition of one or more entities in the semantic network by ID.\n"
				"\n"
				"Supports batch retrieval: pass multiple IDs via entity_ids (preferred when "
				"fetching 2+ entities, saves tool calls), or a single ID via entity_id.\n"
				"Batch results are returned in the 'entities' list (same order as input); "
				"missing IDs are listed in 'not_found'.\n"
				"\n"
				"Applicable scenarios:\n"
				"- After semantic_search finds candidate IDs, get the full SQL and field definitions\n"
				"- Get the full column definitions (columns) of a table\n"
				"- Get the full SQL and category of a metric\n"
				"- Get the full details of a concept (tables, comparisons, decision_guide)\n"
				"- Get the full details of a column_concept (columns, comparisons, decision_guide)"
			),
			"parameters": {
				"type": "object",
				"properties": {
					"entity_id": {
						"type": "string",
						"description": "Single entity ID (for fetching one entity).",
					},
					"entity_ids": {
						"type": "array",
						"items": {"type": "string"},
						"description": "Multiple entity IDs (for batch fetching; preferred over entity_id when fetching 2+ entities).",
					},
				},
			},
		},
	}


def _semantic_list_schema() -> dict[str, Any]:
	"""semantic_list: list entities or relationships with pagination."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_list",
			"description": (
				"List entities or relationships in the semantic network with pagination support.\n"
				"\n"
				"Returns summaries for the specified page. Use page and page_size to navigate through results.\n"
				"\n"
				"Item format varies by type:\n"
				"- Entity types (table/metric/concept/column_concept): {id, name, desc, entity_type}\n"
				"- Relationships (join/relationship): {id, source_entity_id, target_entity_id, relation_type, desc}\n"
				"\n"
				"Applicable scenarios:\n"
				"- Browse all tables/metrics/concepts to understand the semantic network scope\n"
				"- List all join relationships between tables\n"
				"- Check if a specific entity exists before adding/updating\n"
				"- Enumerate entities of a specific type for batch operations\n"
				"- Get an overview of entity counts by type"
			),
			"parameters": {
				"type": "object",
				"properties": {
					"type": {
						"type": "string",
						"description": (
							"What to list. When omitted, all entity types are listed in order: table, metric, concept, column_concept.\n"
							"Entity types: table, metric, concept, column_concept.\n"
							"Relationship types: join (joins only), relationship (all relationships)."
						),
						"enum": ["table", "metric", "concept", "column_concept", "join", "relationship"],
					},
					"page": {
						"type": "integer",
						"description": "Page number (1-based). Default 1.",
						"minimum": 1,
					},
					"page_size": {
						"type": "integer",
						"description": "Number of items per page. Default 20, max 100.",
						"minimum": 1,
						"maximum": 100,
					},
				},
				"required": [],
			},
		},
	}


def _semantic_graph_schema() -> dict[str, Any]:
	"""semantic_graph: graph traversal (neighbors/lineage/reverse metric lookup)."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_graph",
			"description": (
				"Semantic network graph traversal tool, three modes:\n"
				"\n"
				"1. query_neighbors (default): query the relationship neighbors of an entity, with optional direction and relation type filtering; supports table, metric, concept, column_concept.\n"
				"2. trace_lineage: trace the complete lineage of a metric (parse dependent tables from metric SQL)\n"
				"3. metrics_by_table: reverse lookup of metrics that depend on a given table\n"
				"\n"
				"Typical usage:\n"
				"- Which business concepts does a table belong to? → mode=query_neighbors, entity_type=table, direction=incoming (may return relation_type=concept soft reference neighbors)\n"
				"- What candidate tables are under a business concept? → mode=query_neighbors, entity_type=concept, direction=outgoing\n"
				"- Which column-level concepts do a table's columns belong to? → mode=query_neighbors, entity_type=table, direction=incoming, relation_type=column_concept\n"
				"- What candidate columns are under a column-level concept? → mode=query_neighbors, entity_type=column_concept, direction=outgoing\n"
				"- Which tables does a metric depend on? → mode=trace_lineage, metric_id=xxx\n"
				"- Complete lineage tree of a metric? → mode=trace_lineage, metric_id=xxx\n"
				"- Which metrics does this table support? → mode=metrics_by_table, table_id=xxx"
			),
			"parameters": {
				"type": "object",
				"properties": {
					"mode": {
						"type": "string",
						"description": "Traversal mode: query_neighbors(neighbors) / trace_lineage(lineage) / metrics_by_table(reverse metric lookup).",
						"enum": ["query_neighbors", "trace_lineage", "metrics_by_table"],
					},
					"entity_type": {
						"type": "string",
						"description": "Required for mode=query_neighbors: starting entity type.",
						"enum": ["table", "metric", "concept", "column_concept"],
					},
					"entity_id": {
						"type": "string",
						"description": "Required for mode=query_neighbors: starting entity ID.",
					},
					"metric_id": {
						"type": "string",
						"description": "Required for mode=trace_lineage: metric ID to trace lineage for.",
					},
					"table_id": {
						"type": "string",
						"description": "Required for mode=metrics_by_table: table ID.",
					},
					"direction": {
						"type": "string",
						"description": "Optional for mode=query_neighbors: traversal direction. Default both.",
						"enum": ["outgoing", "incoming", "both"],
					},
					"relation_type": {
						"type": "string",
						"description": "Optional for mode=query_neighbors: only return edges of the specified relation type. E.g. joins, concept, column_concept. concept is a soft reference adjacency dynamically generated based on concept.tables, column_concept is a soft reference adjacency dynamically generated based on column_concept.columns.",
					},
					"depth": {
						"type": "integer",
						"description": "Optional for mode=query_neighbors: traversal depth, default 1 (direct neighbors). Max 2.",
						"minimum": 1,
						"maximum": 2,
					},
				},
				"required": ["mode"],
			},
		},
	}


def _semantic_upsert_entity_schema() -> dict[str, Any]:
	"""semantic_upsert_entity: add or update entity (merged add+update)."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_upsert_entity",
			"description": (
				"Add or update an entity in the semantic network (upsert semantics).\n"
				"\n"
				"Behavior:\n"
				"- entity_id already exists → update (merge updates into existing entity)\n"
				"- entity_id does not exist → add new\n"
				"\n"
				"Entity payload field specifications:\n"
				"- table: id(required), name(required), desc(required), columns(dict format: {column_name: {desc: description, default?: default_value}}), synonyms, default_granularity\n"
				"- metric: id(required), name(required), sql(required), desc(required), category(required), synonyms, default_granularity\n"
				"- concept: id(required), name(required), desc(required), tables(array: list of associated table IDs), comparisons(structured comparison array), decision_guide(KV mapping: table selection guide)\n"
				"- column_concept: id(required), name(required), desc(required), columns(array: list of associated column references, format is table_id.column_name), comparisons(structured comparison array), decision_guide(KV mapping: column selection guide)\n"
				"\n"
				"In update mode, entity serves as updates (key is dot-separated field path, value is new value):\n"
				'- {"desc": "new description"} → update desc\n'
				'- {"columns.TERM_CODE.desc": "term code"} → update the desc of TERM_CODE column in columns\n'
				'- {"columns": {"COL1": {"desc": "new description"}}} → deep merge update columns dict'
			),
			"parameters": {
				"type": "object",
				"properties": {
					"entity_type": {
						"type": "string",
						"description": "Entity type.",
						"enum": ["table", "metric", "concept", "column_concept"],
					},
					"entity": {
						"type": "object",
						"description": "Entity payload (when adding) or update content (when updating, key is field path). Must include id.",
					},
					"reason": {
						"type": "string",
						"description": "Required: detailed reason for this operation (explain why the entity is being added/updated based on user needs).",
					},
				},
				"required": ["entity_type", "entity", "reason"],
			},
		},
	}


def _semantic_upsert_relationship_schema() -> dict[str, Any]:
	"""semantic_upsert_relationship: add or update relationship (merged add+update)."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_upsert_relationship",
			"description": (
				"Add or update a relationship edge in the semantic network (upsert semantics).\n"
				"\n"
				"Behavior:\n"
				"- id already exists → update (merge updates into existing relationship)\n"
				"- id does not exist → add new\n"
				"\n"
				"Allowed relationship types:\n"
				"- joins: source table can join with target table (source/target must both be table, column pairs must be specified via columns)\n"
				"\n"
				"columns format (required for joins): [{\"source_column\": \"source table column name\", \"target_column\": \"target table column name\"}, ...]"
			),
			"parameters": {
				"type": "object",
				"properties": {
					"id": {
						"type": "string",
						"description": "Relationship ID.",
					},
					"source_entity_type": {
						"type": "string",
						"description": "Source entity type.",
						"enum": ["table"],
					},
					"source_entity_id": {
						"type": "string",
						"description": "Source entity ID.",
					},
					"target_entity_type": {
						"type": "string",
						"description": "Target entity type.",
						"enum": ["table"],
					},
					"target_entity_id": {
						"type": "string",
						"description": "Target entity ID.",
					},
					"relation_type": {
						"type": "string",
						"description": "Relationship type.",
						"enum": ["joins"],
					},
					"desc": {
						"type": "string",
						"description": "Relationship description.",
					},
					"columns": {
						"type": "array",
						"description": "Required for joins relationships: list of column pairs.",
						"items": {
							"type": "object",
							"properties": {
								"source_column": {"type": "string", "description": "Column name in the source table."},
								"target_column": {"type": "string", "description": "Column name in the target table."},
							},
						},
					},
					"reason": {
						"type": "string",
						"description": "Required: detailed reason for this operation (explain why the relationship is being added/updated based on user needs).",
					},
				},
				"required": ["id", "source_entity_type", "source_entity_id", "target_entity_type", "target_entity_id", "relation_type", "desc", "reason"],
			},
		},
	}


def _semantic_delete_schema() -> dict[str, Any]:
	"""semantic_delete: delete entity or relationship (merged delete_entity+delete_relationship)."""
	return {
		"type": "function",
		"function": {
			"name": "semantic_delete",
			"description": (
				"Delete an entity or relationship in the semantic network.\n"
				"\n"
				"target=entity: delete the entity, and automatically clean up its vector store records and all associated relationship edges (as source or target)\n"
				"target=relationship: only delete the specified relationship edge\n"
				"\n"
				"Applicable scenarios:\n"
				"- When the entity definition is incorrect and cannot be fixed via upsert\n"
				"- When a table is decommissioned and semantic network remnants need cleanup\n"
				"- When the relationship type is mislabeled and needs to be deleted and re-added\n"
				"- When an entity has been deleted and associated orphan relationships need cleanup"
			),
			"parameters": {
				"type": "object",
				"properties": {
					"target": {
						"type": "string",
						"description": "Deletion target: entity or relationship.",
						"enum": ["entity", "relationship"],
					},
					"entity_type": {
						"type": "string",
						"description": "Required for target=entity: entity type.",
						"enum": ["table", "metric", "concept", "column_concept"],
					},
					"entity_id": {
						"type": "string",
						"description": "Required for target=entity: entity ID.",
					},
					"relationship_id": {
						"type": "string",
						"description": "Required for target=relationship: relationship ID.",
					},
					"reason": {
						"type": "string",
						"description": "Required: detailed reason for this deletion.",
					},
				},
				"required": ["target", "reason"],
			},
		},
	}


# ──────────────────────────────────────────────
# Tool Handler Factory
# ──────────────────────────────────────────────


# Semantic tool instance cache: cached by semantic_file to avoid rebuilding config on every call
_semantic_tool_cache: dict[str, SemanticNetworkTool] = {}
_semantic_tool_cache_lock = threading.Lock()


def _resolve_semantic_tool() -> SemanticNetworkTool:
	"""Dynamically build SemanticNetworkTool at call time (with caching).

	Reads semantic_dir from react_config.json, concatenates with the current context's semantic_file
	"""
	from Agent.config_loader import load_config, build_semantic_config

	project_root = Path(__file__).resolve().parents[1]
	config_path = Path(__file__).resolve().parent / "react_config.json"
	config_data = load_config(config_path)
	semantic_config = build_semantic_config(config_data)

	# Context-level semantic_file
	ctx = get_current_context()
	session_file = ctx.semantic_file if ctx else ""

	# Cache key: cache tool instance by semantic_file
	cache_key = session_file or "default"

	# Fast path: lock-free cache check (return directly on hit)
	cached = _semantic_tool_cache.get(cache_key)
	if cached is not None:
		return cached

	# Slow path: double-checked locking after acquiring lock, to avoid concurrent creation of multiple instances
	with _semantic_tool_cache_lock:
		cached = _semantic_tool_cache.get(cache_key)
		if cached is not None:
			return cached

		if not session_file:
			tool = SemanticNetworkTool(semantic_config)
			_semantic_tool_cache[cache_key] = tool
			return tool

		file_name = str(session_file)
		semantic_dir = semantic_config.semantic_dir
		if semantic_dir:
			base_dir = Path(semantic_dir).expanduser()
			if not base_dir.is_absolute():
				base_dir = (project_root / base_dir).resolve()
			file_path = base_dir / file_name
		else:
			file_path = Path(file_name).expanduser()
			if not file_path.is_absolute():
				file_path = (project_root / file_path).resolve()
		semantic_config.yaml_path = str(file_path)

		tool = SemanticNetworkTool(semantic_config)
		_semantic_tool_cache[cache_key] = tool
		return tool


# ──────────────────────────────────────────────
# Generic validation helper (eliminates handler boilerplate)
# ──────────────────────────────────────────────


def _require(args: dict[str, Any], fields: list[str]) -> dict[str, Any] | None:
	"""Validate required fields, return error dict or None."""
	for field in fields:
		val = args.get(field, "")
		if isinstance(val, str):
			val = val.strip()
		if not val:
			return {"ok": False, "error": f"{field} is required"}
	return None


# ──────────────────────────────────────────────
# Merged Handlers (6 semantic tools)
# ──────────────────────────────────────────────


def _semantic_search_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_search: vector semantic retrieval."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err
	query = str(args.get("query", "")).strip()
	if not query:
		return {"ok": False, "error": "query is required"}
	tool = _resolve_semantic_tool()
	entity_type_raw = args.get("entity_type")
	entity_type = str(entity_type_raw or "").strip().lower() or None
	if entity_type and entity_type not in tool._supported_entity_types():
		return {"ok": False, "error": f"Unsupported entity_type: {entity_type}"}
	topk = int(args.get("topk", 10))
	store = tool._get_vector_store()
	if store is None:
		return {"ok": False, "error": "Vector store not enabled (vector_db_dir not configured)"}
	# Search the specified entity type; when not provided, default to searching all entity types with independent topk each
	result = store.search(query=query, entity_type=entity_type, topk=topk)
	if not result.get("ok"):
		return result
	# Supplement desc from YAML, and clean up internal fields, ultimately each item only retains id and desc
	doc = tool._load()
	for items in result.get("items_by_type", {}).values():
		for item in items:
			eid = item.get("id", "")
			etype = item.get("entity_type", "")
			full_entity = tool._get_entity_full(doc, etype, eid)
			desc = str(full_entity.get("desc", "")) if full_entity else ""
			# In-place cleanup: only retain id and desc
			item.clear()
			item["id"] = eid
			item["desc"] = desc
			# semantic_search does not return relationships; use semantic_graph to get relationships
	return result


def _semantic_get_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_get: get entity details by ID (single entity_id or batch entity_ids)."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err

	# Batch parameter entity_ids takes priority; single entity_id is also supported
	ids_raw = args.get("entity_ids")
	entity_ids: list[str] = []
	if isinstance(ids_raw, list):
		entity_ids = [str(i).strip() for i in ids_raw if str(i).strip()]
	elif isinstance(ids_raw, str) and ids_raw.strip():
		# Fault tolerance: the LLM may pass a comma-separated string
		entity_ids = [s.strip() for s in ids_raw.split(",") if s.strip()]

	if not entity_ids:
		single = str(args.get("entity_id", "")).strip()
		if single:
			entity_ids = [single]

	if not entity_ids:
		return {"ok": False, "error": "entity_id or entity_ids is required"}

	tool = _resolve_semantic_tool()
	if len(entity_ids) == 1:
		return tool.semantic_get_entity(entity_id=entity_ids[0])
	return tool.semantic_get_entities(entity_ids=entity_ids)


def _semantic_list_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_list: list entities or relationships with pagination."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err
	type_raw = args.get("type")
	type_val = str(type_raw or "").strip().lower() or None
	page = int(args.get("page", 1))
	page_size = int(args.get("page_size", 20))
	if page < 1:
		page = 1
	if page_size < 1:
		page_size = 20
	if page_size > 100:
		page_size = 100
	tool = _resolve_semantic_tool()
	return tool.list_entities(type=type_val, page=page, page_size=page_size)


def _semantic_graph_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_graph: graph traversal (neighbors/lineage/reverse metric lookup)."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err
	mode = str(args.get("mode", "")).strip()
	if not mode:
		return {"ok": False, "error": "mode is required"}
	tool = _resolve_semantic_tool()

	if mode == "query_neighbors":
		entity_type = str(args.get("entity_type", "")).strip()
		entity_id = str(args.get("entity_id", "")).strip()
		if not entity_type:
			return {"ok": False, "error": "entity_type is required"}
		if not entity_id:
			return {"ok": False, "error": "entity_id is required"}
		direction = str(args.get("direction", "both")).strip() or "both"
		relation_type = str(args.get("relation_type", "")).strip() or None
		depth = int(args.get("depth", 1))
		return tool.semantic_query_neighbors(
			entity_type=entity_type,
			entity_id=entity_id,
			direction=direction,
			relation_type=relation_type,
			depth=depth,
		)

	if mode == "trace_lineage":
		metric_id = str(args.get("metric_id", "")).strip()
		if not metric_id:
			return {"ok": False, "error": "metric_id is required"}
		return tool.semantic_trace_lineage(metric_id=metric_id)

	if mode == "metrics_by_table":
		table_id = str(args.get("table_id", "")).strip()
		if not table_id:
			return {"ok": False, "error": "table_id is required"}
		return tool.semantic_query_metrics_by_table(table_id=table_id)

	return {"ok": False, "error": f"Unsupported mode: {mode}"}


def _semantic_upsert_entity_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_upsert_entity: add or update entity."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err
	entity_type = str(args.get("entity_type", "")).strip()
	entity = args.get("entity")

	# Validate
	verr = _require(args, ["entity_type", "reason"])
	if verr:
		return verr
	if not isinstance(entity, dict):
		return {"ok": False, "error": "entity must be an object"}

	entity_id = str(entity.get("id", "")).strip()
	if not entity_id:
		return {"ok": False, "error": "entity.id is required"}

	tool = _resolve_semantic_tool()
	doc = tool._load()
	tool._ensure_collections(doc)
	exists = tool._entity_exists(doc, entity_type, entity_id)

	if exists:
		# Update mode: entity serves as updates
		return tool.update_entity(entity_type=entity_type, entity_id=entity_id, updates=entity)
	return tool.add_entity(entity_type=entity_type, entity=entity)


def _semantic_upsert_relationship_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_upsert_relationship: add or update relationship."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err

	# Validate required fields
	required_keys = ["id", "source_entity_type", "source_entity_id", "target_entity_type", "target_entity_id", "relation_type", "desc", "reason"]
	verr = _require(args, required_keys)
	if verr:
		return verr

	rid = str(args["id"]).strip()
	tool = _resolve_semantic_tool()
	doc = tool._load()
	tool._ensure_collections(doc)
	exists = tool._find_by_id(doc.get("relationships", []), rid) is not None

	if exists:
		# Update mode: build updates dict
		updates = {
			"source_entity_type": str(args["source_entity_type"]),
			"source_entity_id": str(args["source_entity_id"]),
			"target_entity_type": str(args["target_entity_type"]),
			"target_entity_id": str(args["target_entity_id"]),
			"relation_type": str(args["relation_type"]),
			"desc": str(args["desc"]),
		}
		if args.get("columns") is not None:
			updates["columns"] = args["columns"]
		return tool.update_relationship(relationship_id=rid, updates=updates)
	return tool.add_relationship(
		relationship_id=rid,
		source_entity_type=str(args["source_entity_type"]),
		source_entity_id=str(args["source_entity_id"]),
		target_entity_type=str(args["target_entity_type"]),
		target_entity_id=str(args["target_entity_id"]),
		relation_type=str(args["relation_type"]),
		desc=str(args["desc"]),
		columns=args.get("columns"),
	)


def _semantic_delete_handler(raw_arguments: str) -> dict[str, Any]:
	"""semantic_delete: delete entity or relationship."""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err
	target = str(args.get("target", "")).strip()

	verr = _require(args, ["target", "reason"])
	if verr:
		return verr

	tool = _resolve_semantic_tool()

	if target == "entity":
		entity_type = str(args.get("entity_type", "")).strip()
		entity_id = str(args.get("entity_id", "")).strip()
		if not entity_type:
			return {"ok": False, "error": "entity_type is required"}
		if not entity_id:
			return {"ok": False, "error": "entity_id is required"}
		return tool.delete_entity(entity_type=entity_type, entity_id=entity_id)

	if target == "relationship":
		rid = str(args.get("relationship_id", "")).strip()
		if not rid:
			return {"ok": False, "error": "relationship_id is required"}
		return tool.delete_relationship(relationship_id=rid)

	return {"ok": False, "error": f"Unsupported target: {target}"}


# ──────────────────────────────────────────────
# Submit SQL Tool (submit_SQL)
# ──────────────────────────────────────────────


def _submit_sql_schema() -> dict[str, Any]:
	"""submit_SQL tool schema: submit the final SQL answer."""
	return {
		"type": "function",
		"function": {
			"name": "submit_SQL",
			"description": (
				"Submit the final SQL query that answers the user's question. "
				"Call this tool exactly once when the final SQL is ready."
			),
			"parameters": {
				"type": "object",
				"properties": {
					"sql": {
						"type": "string",
						"description": "The final SQL query to submit.",
					},
				},
				"required": ["sql"],
			},
		},
	}


def _submit_sql_handler(raw_arguments: str) -> dict[str, Any]:
	"""submit_SQL handler: writes the final SQL in BEAVER unified-output format.

	When the runtime context provides `generated_dir` (batch runs via
	pipeline.py), the SQL is written directly to `{generated_dir}/{case}.sql`
	(the official BEAVER evaluation format; later submissions overwrite
	earlier ones). Otherwise (e.g. interactive CLI), it is appended to
	`Eval/submitted_sql.jsonl` as a fallback log.
	"""
	args, err = parse_tool_args(raw_arguments)
	if err:
		return err

	sql = str(args.get("sql", "")).strip()
	if not sql:
		return {"ok": False, "error": "sql is required"}

	# Get current case identifier from runtime context (case_id in batch mode)
	ctx = get_current_context()
	case = ""
	session_id = ""
	generated_dir = ""
	if ctx is not None:
		case = ctx.case_id or ""
		session_id = ctx.session_id or ""
		generated_dir = getattr(ctx, "generated_dir", "") or ""

	# Batch mode: write directly to unified-output/.../generated/{case}.sql
	if generated_dir and case:
		try:
			out_path = Path(generated_dir) / f"{case}.sql"
			out_path.parent.mkdir(parents=True, exist_ok=True)
			out_path.write_text(sql, encoding="utf-8")
		except Exception as e:
			return {"ok": False, "error": f"Failed to write submitted SQL file: {e}"}
		return {
			"ok": True,
			"case": case,
			"message": "SQL submitted successfully.",
		}

	# Fallback (interactive CLI etc.): append to Eval/submitted_sql.jsonl
	eval_dir = Path(__file__).resolve().parent.parent / "Eval"
	eval_dir.mkdir(parents=True, exist_ok=True)
	submitted_path = eval_dir / "submitted_sql.jsonl"

	record = {
		"case": case,
		"session_id": session_id,
		"sql": sql,
		"timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
	}

	try:
		import json
		with open(submitted_path, "a", encoding="utf-8") as f:
			f.write(json.dumps(record, ensure_ascii=False) + "\n")
	except Exception as e:
		return {"ok": False, "error": f"Failed to write submitted SQL file: {e}"}

	return {
		"ok": True,
		"case": case,
		"message": "SQL submitted successfully.",
	}


# ──────────────────────────────────────────────
# Register All Tools
# ──────────────────────────────────────────────

_TOOLS_REGISTERED = False


def register_all_tools(mysql_tool: MySQLTool) -> None:
	"""Register all basic tools to the global registry.

	Only registers on first call (idempotent). mysql_tool is isolated per request via ContextVar,
	to avoid handler closures overwriting each other during concurrent requests.
	"""
	global _TOOLS_REGISTERED
	if _TOOLS_REGISTERED:
		# Tools already registered, only update the current request's mysql_tool
		set_current_mysql_tool(mysql_tool)
		return

	def _mysql_query_handler(raw_arguments: str) -> dict[str, Any]:
		from Agent.common import get_current_mysql_tool
		tool = get_current_mysql_tool()
		if tool is None:
			return {"ok": False, "error": "MySQL tool not initialized"}
		args, err = parse_tool_args(raw_arguments)
		if err:
			return err
		sql = str(args.get("sql", "")).strip()
		if not sql:
			return {"ok": False, "error": "sql is required"}
		return tool.execute_query(sql)

	register_tool("mysql_query", _mysql_query_schema(), _mysql_query_handler)
	register_tool("semantic_search", _semantic_search_schema(), _semantic_search_handler)
	register_tool("semantic_get", _semantic_get_schema(), _semantic_get_handler)
	register_tool("semantic_list", _semantic_list_schema(), _semantic_list_handler)
	register_tool("semantic_graph", _semantic_graph_schema(), _semantic_graph_handler)
	register_tool("semantic_upsert_entity", _semantic_upsert_entity_schema(), _semantic_upsert_entity_handler)
	register_tool("semantic_upsert_relationship", _semantic_upsert_relationship_schema(), _semantic_upsert_relationship_handler)
	register_tool("semantic_delete", _semantic_delete_schema(), _semantic_delete_handler)
	register_tool("submit_SQL", _submit_sql_schema(), _submit_sql_handler)

	_TOOLS_REGISTERED = True
	set_current_mysql_tool(mysql_tool)
