"""Persistent application conversation keys bound to web-chat URLs."""

from __future__ import annotations

import os
import re
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional
from urllib.parse import urlparse, urlunparse


_KEY_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:._-]{0,199}$")


def normalize_conversation_key(value: object) -> str:
    key = str(value or "").strip()
    if not key:
        return ""
    if not _KEY_PATTERN.fullmatch(key):
        raise ValueError(
            "conversation_key must be 1-200 characters using letters, numbers, ':', '.', '_' or '-'"
        )
    return key


def normalize_conversation_title(value: object) -> str:
    return " ".join(str(value or "").split())[:120]


def is_conversation_url(route_domain: str, url: object) -> bool:
    domain = str(route_domain or "").strip().lower()
    raw_url = str(url or "").strip()
    if not domain or not raw_url:
        return False
    try:
        parsed = urlparse(raw_url)
    except Exception:
        return False
    host = str(parsed.hostname or "").strip().lower()
    path = str(parsed.path or "")
    if parsed.scheme != "https" or parsed.username or parsed.password:
        return False
    if host != domain and not host.endswith(f".{domain}"):
        return False
    if domain in {"chat.qwen.ai", "www.chat.qwen.ai"}:
        return bool(re.fullmatch(r"/(?:c|chat)/(?!guest/?$)[A-Za-z0-9_-]+/?", path))
    return path not in {"", "/"}


def continuation_messages(messages: object) -> list[dict[str, Any]]:
    source = messages if isinstance(messages, list) else []
    for message in reversed(source):
        if (
            isinstance(message, dict)
            and str(message.get("role") or "").strip().lower() == "user"
            and str(message.get("name") or "").strip() != "dsh_context"
        ):
            return [dict(message)]
    return []


@dataclass(frozen=True)
class ConversationBinding:
    key: str
    route_domain: str
    conversation_url: str
    created_at: float
    updated_at: float


@dataclass(frozen=True)
class BoundConversationPlan:
    key: str
    route_domain: str
    conversation_url: Optional[str]
    preset_name: Optional[str]
    reuse_current_conversation: bool
    messages: list[dict[str, Any]]


class ConversationBindingStore:
    """Small SQLite repository with atomic per-call reads and writes."""

    def __init__(self, database_path: os.PathLike[str] | str):
        self.database_path = Path(database_path)
        self._schema_lock = threading.Lock()
        self._schema_ready = False

    def _connect(self) -> sqlite3.Connection:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(str(self.database_path), timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def _ensure_schema(self) -> None:
        if self._schema_ready:
            return
        with self._schema_lock:
            if self._schema_ready:
                return
            with self._connect() as connection:
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS conversation_bindings (
                        conversation_key TEXT PRIMARY KEY,
                        route_domain TEXT NOT NULL,
                        conversation_url TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE UNIQUE INDEX IF NOT EXISTS
                    idx_conversation_bindings_url
                    ON conversation_bindings(route_domain, conversation_url)
                    """
                )
            self._schema_ready = True

    def get(self, key: object) -> Optional[ConversationBinding]:
        normalized_key = normalize_conversation_key(key)
        if not normalized_key:
            return None
        self._ensure_schema()
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT conversation_key, route_domain, conversation_url, created_at, updated_at
                FROM conversation_bindings
                WHERE conversation_key = ?
                """,
                (normalized_key,),
            ).fetchone()
        if row is None:
            return None
        return ConversationBinding(
            key=str(row["conversation_key"]),
            route_domain=str(row["route_domain"]),
            conversation_url=str(row["conversation_url"]),
            created_at=float(row["created_at"]),
            updated_at=float(row["updated_at"]),
        )

    def bind(
        self,
        *,
        key: object,
        route_domain: str,
        conversation_url: str,
    ) -> ConversationBinding:
        normalized_key = normalize_conversation_key(key)
        if not normalized_key:
            raise ValueError("conversation_key is required")
        normalized_domain = str(route_domain or "").strip().lower()
        normalized_url = str(conversation_url or "").strip()
        if not normalized_domain or not normalized_url:
            raise ValueError("route_domain and conversation_url are required")

        if not is_conversation_url(normalized_domain, normalized_url):
            raise ValueError("A durable HTTPS conversation URL is required")
        parsed = urlparse(normalized_url)
        normalized_url = urlunparse((parsed.scheme, parsed.hostname, parsed.path.rstrip("/"), "", "", ""))
        self._ensure_schema()
        now = time.time()
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO conversation_bindings (
                    conversation_key, route_domain, conversation_url, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(conversation_key) DO UPDATE SET
                    route_domain = excluded.route_domain,
                    conversation_url = excluded.conversation_url,
                    updated_at = excluded.updated_at
                """,
                (normalized_key, normalized_domain, normalized_url, now, now),
            )
        binding = self.get(normalized_key)
        if binding is None:
            raise RuntimeError("conversation binding was not persisted")
        return binding

    def delete(self, key: object) -> bool:
        normalized_key = normalize_conversation_key(key)
        if not normalized_key:
            return False
        self._ensure_schema()
        with self._connect() as connection:
            cursor = connection.execute(
                "DELETE FROM conversation_bindings WHERE conversation_key = ?",
                (normalized_key,),
            )
            return cursor.rowcount > 0

    def list_for_route_domain(self, route_domain: str) -> list[ConversationBinding]:
        """Return durable bindings from least to most recently used."""
        normalized_domain = str(route_domain or "").strip().lower()
        if not normalized_domain:
            return []
        self._ensure_schema()
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT conversation_key, route_domain, conversation_url, created_at, updated_at
                FROM conversation_bindings
                WHERE route_domain = ?
                ORDER BY updated_at ASC, created_at ASC, conversation_key ASC
                """,
                (normalized_domain,),
            ).fetchall()
        return [
            ConversationBinding(
                key=str(row["conversation_key"]),
                route_domain=str(row["route_domain"]),
                conversation_url=str(row["conversation_url"]),
                created_at=float(row["created_at"]),
                updated_at=float(row["updated_at"]),
            )
            for row in rows
        ]


def plan_bound_request(
    *,
    store: ConversationBindingStore,
    key: object,
    route_domain: str,
    messages: object,
) -> BoundConversationPlan:
    normalized_key = normalize_conversation_key(key)
    normalized_domain = str(route_domain or "").strip().lower()
    source_messages = [dict(item) for item in messages if isinstance(item, dict)] \
        if isinstance(messages, list) else []
    # A single user message in a bound web conversation is already complete.
    # Mark it here as well because an OpenAI proxy may discard extra fields.
    if len(source_messages) == 1 and source_messages[0].get("role") == "user":
        source_messages[0]["pdflight_verbatim"] = True
    binding = store.get(normalized_key)
    if binding is None:
        return BoundConversationPlan(
            key=normalized_key,
            route_domain=normalized_domain,
            conversation_url=None,
            preset_name=None,
            reuse_current_conversation=False,
            messages=source_messages,
        )
    if binding.route_domain != normalized_domain:
        raise ValueError("conversation_key is already bound to another route domain")
    return BoundConversationPlan(
        key=normalized_key,
        route_domain=normalized_domain,
        conversation_url=binding.conversation_url,
        preset_name=None,
        reuse_current_conversation=True,
        messages=continuation_messages(source_messages),
    )


def conversation_metadata(key: str, url: object = None, state: str = "pending") -> dict[str, Any]:
    """Public binding data only; never include query strings or browser credentials."""
    raw = str(url or "").strip()
    safe_url = None
    if is_conversation_url("chat.qwen.ai", raw):
        parsed = urlparse(raw)
        safe_url = urlunparse(("https", parsed.hostname, parsed.path.rstrip("/"), "", "", ""))
    return {
        "conversation_key": key,
        "client_session_id": key,
        "conversation_id": safe_url.rsplit("/", 1)[-1] if safe_url else None,
        "conversation_url": safe_url,
        "conversation_state": state if safe_url else "pending",
    }


conversation_binding_store = ConversationBindingStore(
    os.getenv("CONVERSATION_BINDINGS_DB", "config/conversation_bindings.sqlite3")
)


__all__ = [
    "ConversationBinding",
    "ConversationBindingStore",
    "BoundConversationPlan",
    "continuation_messages",
    "conversation_binding_store",
    "conversation_metadata",
    "is_conversation_url",
    "normalize_conversation_key",
    "normalize_conversation_title",
    "plan_bound_request",
]
