"""Zvec vector store wrapper: vector storage and retrieval for semantic network entities.

Each entity_type (table/metric/concept/column_concept) maps to an independent zvec collection.
The document ID is the MD5 hash of entity_type+entity_id (fixed 32 characters,
unaffected by entity ID length/character restrictions); the entity's raw information
is stored as metadata fields.

Vectorized text: name + synonyms + desc concatenated and embedded.

Dependencies:
- zvec (vector database)
- OpenAIDenseEmbedding (calls the embedding model via an OpenAI-compatible endpoint, e.g. DashScope)
"""

from __future__ import annotations

import hashlib
import threading
from pathlib import Path
from typing import Any, Callable

import zvec
from zvec import DataType, MetricType
from zvec.extension import OpenAIDenseEmbedding

from env_config import get_env

# Supported entity types -> collection suffix
ENTITY_TYPES = [
	"table",
	"metric",
	"concept",
	"column_concept",
]


class SemanticVectorStore:
	"""Manages the vector collections of semantic network entities.

	- One collection per entity type: <db_dir>/semantic_<etype>
	- Document ID: MD5(entity_type:entity_id), fixed 32 characters
	- Metadata fields: entity_id, name, entity_type, synonyms
	- Vector field: embedding (embedding of the name + synonyms + desc text)
	- Thread-safe: locks are held when writing collections concurrently (zvec collections are not thread-safe)
	"""

	# Class-level zvec initialization flag (replaces a module-level global variable)
	_zvec_initialized: bool = False

	def __init__(
		self,
		db_dir: str,
		base_url: str = "",
		model: str = "qwen3.7-text-embedding",
		dimension: int = 1024,
		topk: int = 10,
	) -> None:
		self.db_dir = str(db_dir)
		self.base_url = str(base_url)
		self.model = model
		self.dimension = int(dimension)
		self.topk = int(topk)
		self._embed = None
		self._collections: dict[str, zvec.Collection] = {}
		self._lock = threading.Lock()
		# lazy init: call zvec.init once
		self._init_once()


	def _init_once(self) -> None:
		"""Ensure zvec is initialized only once."""
		if not SemanticVectorStore._zvec_initialized:
			zvec.init()
			SemanticVectorStore._zvec_initialized = True

	

	def _embed_func(self) -> OpenAIDenseEmbedding:
		"""Lazily load the embedding function (URL and API key both come from the repo-root .env)."""
		if self._embed is None:
			api_key = get_env("EMBEDDING_API_KEY")
			if not api_key:
				raise ValueError("Missing EMBEDDING_API_KEY (please set it in the repo-root .env)")
			if not self.base_url:
				raise ValueError("Missing EMBEDDING_BASE_URL (please set it in the repo-root .env)")
			self._embed = OpenAIDenseEmbedding(
				model=self.model,
				dimension=self.dimension,
				api_key=api_key,
				base_url=self.base_url,
			)
		return self._embed

	@staticmethod
	def _doc_id(etype: str, entity_id: str) -> str:
		"""Generate a fixed 32-character document ID (MD5 hash), unaffected by entity ID length/character restrictions."""
		return hashlib.md5(f"{etype}:{entity_id}".encode("utf-8")).hexdigest()

	@staticmethod
	def _build_text(name: str, desc: str, synonyms: list[str] | None) -> str:
		"""Build the vectorized text: name + synonyms + desc concatenated."""
		parts = [name]
		if synonyms:
			parts.extend(synonyms)
		parts.append(desc)
		return "\n".join(p for p in parts if p and p.strip()).strip()

	def _collection_path(self, etype: str) -> str:
		"""Return the directory path of the collection for a given entity type."""
		return str(Path(self.db_dir) / f"semantic_{etype}")

	@staticmethod
	def _ensure_lock_file(path: str) -> None:
		"""Ensure the LOCK file exists (zvec.open does not create LOCK, it only flocks it).

		zvec.create_and_open creates the LOCK file, but zvec.open requires it to already exist.
		After a process crash the LOCK file may remain (flock released but file present),
		or it may have been deleted manually.
		This method ensures the LOCK file exists without affecting flock semantics.
		"""
		lock_path = Path(path) / "LOCK"
		if not lock_path.exists():
			try:
				lock_path.touch()
			except Exception:
				pass

	@staticmethod
	def _cleanup_stale_locks(path: str) -> None:
		"""Clean up potentially stale lock files (collection level + idmap subdirectory level).

		After an abnormal process exit, the OS releases the flock but the LOCK file stays on disk.
		These stale LOCK files themselves do not prevent a new process from acquiring the lock,
		but if the LOCK file does not exist, zvec.open reports 'Can't open lock file'.
		This method is used as a last resort when a lock error occurs.
		"""
		for lock_path in [Path(path) / "LOCK", Path(path) / "idmap.0" / "LOCK"]:
			try:
				if lock_path.exists():
					lock_path.unlink()
			except Exception:
				pass

	def _open_with_retry(self, path: str, read_only: bool = False) -> zvec.Collection:
		"""Open a collection; on lock errors, clean up stale locks and retry.

		zvec uses flock file locks:
		- RW mode: only 1 connection per collection (across processes/threads)
		- RO mode: multiple RO connections may coexist, but are mutually exclusive with RW
		- After a process crash the flock is released automatically, but the LOCK file remains
		"""
		option = zvec.CollectionOption(read_only=read_only)
		try:
			return zvec.open(path, option)
		except RuntimeError as e:
			err_msg = str(e)
			# Lock error: clean up stale locks and retry once
			if "lock" in err_msg.lower():
				self._cleanup_stale_locks(path)
				self._ensure_lock_file(path)
				return zvec.open(path, option)
			raise

	def _get_collection(self, etype: str) -> zvec.Collection | None:
		"""Get (creating if necessary) the collection for an entity type (read-write mode)."""
		if etype not in ENTITY_TYPES:
			return None
		with self._lock:
			if etype in self._collections:
				return self._collections[etype]
			path = self._collection_path(etype)
			# Ensure the parent directory exists (but do not create the collection directory itself; zvec must create it)
			Path(path).parent.mkdir(parents=True, exist_ok=True)
			# If the path already exists, open it directly (may be a previously created collection)
			if Path(path).exists():
				self._ensure_lock_file(path)
				coll = self._open_with_retry(path, read_only=False)
				self._collections[etype] = coll
				return coll
			# Path does not exist; create a new collection
			fields = [
				zvec.FieldSchema("entity_id", DataType.STRING),
				zvec.FieldSchema("name", DataType.STRING),
				zvec.FieldSchema("entity_type", DataType.STRING),
				zvec.FieldSchema("synonyms", DataType.ARRAY_STRING),
			]
			schema = zvec.CollectionSchema(
				name=f"semantic_{etype}",
				fields=fields,
				vectors=zvec.VectorSchema(
					"embedding",
					DataType.VECTOR_FP32,
					dimension=self.dimension,
					index_param=zvec.HnswIndexParam(metric_type=MetricType.COSINE),
				),
			)
			coll = zvec.create_and_open(path, schema)
			self._collections[etype] = coll
			return coll

	def _get_read_only_collection(self, etype: str) -> zvec.Collection | None:
		"""Get a read-only collection (used for search).

		zvec lock rules: multiple RO connections may coexist, but RW and RO are mutually exclusive.
		search uses RO mode, allowing concurrent retrieval across processes/threads.
		If RO fails (possibly because the same process already holds RW), fall back to the cached RW collection.
		"""
		if etype not in ENTITY_TYPES:
			return None
		path = self._collection_path(etype)
		if not Path(path).exists():
			return None
		try:
			self._ensure_lock_file(path)
			return self._open_with_retry(path, read_only=True)
		except Exception as exc:
			# RO failed; fall back to the cached RW collection (within the same process)
			print(f"[warning] failed to open {etype} collection in RO mode: {exc}")
			return self._collections.get(etype)

	def _is_enabled(self) -> bool:
		"""Check whether the vector store is available (directory and URL configured, and the key is ready in .env)."""
		if not self.db_dir:
			return False
		if not self.base_url:
			return False
		key = get_env("EMBEDDING_API_KEY")
		return bool(key)

	def upsert_entity(
		self,
		etype: str,
		entity_id: str,
		name: str,
		desc: str,
		synonyms: list[str] | None = None,
	) -> dict[str, Any]:
		"""Insert/update the vector of an entity."""
		if not self._is_enabled():
			return {"ok": False, "error": "Vector store not enabled (missing db_dir or API key)"}
		coll = self._get_collection(etype)
		if coll is None:
			return {"ok": False, "error": f"Unsupported entity type: {etype}"}
		# Embed the name + synonyms + desc text
		text = self._build_text(name, desc, synonyms)
		if not text:
			return {"ok": False, "error": "name/desc is empty; cannot vectorize"}
		vector = self._embed_func().embed(text)
		doc = zvec.Doc(
			id=self._doc_id(etype, entity_id),
			fields={
				"entity_id": entity_id,
				"name": name,
				"entity_type": etype,
				"synonyms": synonyms or [],
			},
			vectors={"embedding": vector},
		)
		with self._lock:
			coll.upsert(doc)
			coll.flush()
		return {"ok": True, "entity_id": entity_id, "entity_type": etype}

	def _batch_embed_and_write(
		self,
		items: list[Any],
		*,
		label: Callable[[Any], str],
		embed_text: Callable[[Any], str],
		write: Callable[[Any, list[float]], None],
		max_workers: int,
		on_progress: "Callable[[int, int, int], None] | None",
	) -> dict[str, Any]:
		"""Shared batch pipeline: concurrent embedding + serial writing + progress callback + final flush.

		Args:
			items: work items (any tuple shape the caller defines)
			label: renders an item for error messages
			embed_text: builds the text to embed for an item (empty string skips the item)
			write: upserts the embedded vector for an item (must handle locking itself)
		"""
		from concurrent.futures import ThreadPoolExecutor, as_completed

		emb = self._embed_func()
		total = len(items)
		success = 0
		errors = 0
		done = 0

		def _embed_one(item: Any) -> tuple[Any, list[float] | None]:
			text = embed_text(item)
			if not text:
				return item, None
			try:
				return item, emb.embed(text)
			except Exception as exc:
				print(f"\n  [embedding error] {label(item)}: {exc}")
				return item, None

		with ThreadPoolExecutor(max_workers=max_workers) as pool:
			futures = {pool.submit(_embed_one, item): item for item in items}
			for future in as_completed(futures):
				item, vec = future.result()
				if vec is None:
					errors += 1
				else:
					try:
						write(item, vec)
						success += 1
					except Exception as exc:
						errors += 1
						print(f"\n  [write error] {label(item)}: {exc}")
				done += 1
				if on_progress:
					on_progress(done, total, errors)

		# Flush all collections once after the batch completes
		with self._lock:
			for coll in self._collections.values():
				coll.flush()

		return {"ok": True, "total": total, "success": success, "errors": errors}

	def batch_upsert(
		self,
		items: list[tuple[str, str, str, str, list[str] | None]],
		max_workers: int = 8,
		on_progress: "Callable[[int, int, int], None] | None" = None,
	) -> dict[str, Any]:
		"""Batch concurrent embedding + serial vector writing.

		Args:
			items: [(entity_type, entity_id, name, desc, synonyms), ...]
			max_workers: number of threads for concurrent embedding
			on_progress: callback (done, total, errors), invoked once per completed entity

		Returns:
			{"ok": True, "total": N, "success": N, "errors": N}
		"""
		if not self._is_enabled():
			return {"ok": False, "error": "Vector store not enabled"}
		if not items:
			return {"ok": True, "total": 0, "success": 0, "errors": 0}

		# Pre-create all needed collections (serially, to avoid concurrent creation conflicts)
		needed_types = {item[0] for item in items if item[0] in ENTITY_TYPES}
		for etype in needed_types:
			self._get_collection(etype)

		def _label(item: tuple[str, str, str, str, list[str] | None]) -> str:
			return f"{item[0]}/{item[1]}"

		def _embed_text(item: tuple[str, str, str, str, list[str] | None]) -> str:
			return self._build_text(item[2], item[3], item[4])

		def _write(item: tuple[str, str, str, str, list[str] | None], vec: list[float]) -> None:
			etype, eid, name, _desc, syns = item
			coll = self._collections.get(etype)
			if coll is None:
				raise RuntimeError(f"collection not available for entity type: {etype}")
			doc = zvec.Doc(
				id=self._doc_id(etype, eid),
				fields={"entity_id": eid, "name": name, "entity_type": etype, "synonyms": syns or []},
				vectors={"embedding": vec},
			)
			with self._lock:
				coll.upsert(doc)

		return self._batch_embed_and_write(
			items,
			label=_label,
			embed_text=_embed_text,
			write=_write,
			max_workers=max_workers,
			on_progress=on_progress,
		)

	def delete_entity(self, etype: str, entity_id: str) -> dict[str, Any]:
		"""Delete the vector of an entity."""
		if not self._is_enabled():
			return {"ok": False, "error": "Vector store not enabled"}
		coll = self._get_collection(etype)
		if coll is None:
			return {"ok": False, "error": f"Unsupported entity type: {etype}"}
		with self._lock:
			coll.delete(self._doc_id(etype, entity_id))
			coll.flush()
		return {"ok": True, "entity_id": entity_id}

	def search(
		self,
		query: str,
		entity_type: str | None = None,
		topk: int | None = None,
	) -> dict[str, Any]:
		"""Vector similarity search. Can search within a specific entity type collection, or across all collections."""
		if not self._is_enabled():
			return {"ok": False, "error": "Vector store not enabled (missing db_dir or API key)"}
		topk = topk or self.topk
		query_vector = self._embed_func().embed(query)

		supported_types = ["table", "metric", "concept", "column_concept"]
		if entity_type:
			if entity_type not in supported_types:
				return {"ok": False, "error": f"Unsupported entity type: {entity_type}"}
			types = [entity_type]
		else:
			types = supported_types

		items_by_type: dict[str, list[dict[str, Any]]] = {}
		for etype in types:
			# search uses RO mode, allowing concurrent retrieval across processes/threads
			coll = self._get_read_only_collection(etype)
			items_by_type[etype] = []
			if coll is None:
				continue
			try:
				q = zvec.Query(
					field_name="embedding",
					vector=query_vector,
					param=zvec.HnswQueryParam(ef=min(300, max(64, topk * 4))),
				)
				docs = coll.query(
					queries=q,
					topk=topk,
					output_fields=["entity_id", "name", "entity_type", "synonyms"],
				)
				for d in docs:
					fields = d.fields or {}
					item = {
						"entity_type": etype,
						"id": fields.get("entity_id", d.id),
						"score": float(d.score) if d.score is not None else 0.0,
					}
					items_by_type[etype].append(item)
			except Exception as exc:
				# A single collection query failure does not abort the whole search; print the error for diagnosis
				print(f"[warning] failed to search {etype} collection: {exc}")
				continue

		total = sum(len(v) for v in items_by_type.values())
		return {
			"ok": True,
			"count": total,
			"items_by_type": items_by_type,
		}
