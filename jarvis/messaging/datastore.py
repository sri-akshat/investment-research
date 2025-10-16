"""Data store abstractions for persisting ingested messages."""
from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Iterable, Protocol

from .models import Attachment, Message


class DataStore(Protocol):
    """Persist messages in a backend of choice."""

    def save_messages(self, messages: Iterable[Message]) -> None:
        """Persist the provided messages."""
        raise NotImplementedError


class SQLiteDataStore:
    """SQLite-backed message data store."""

    def __init__(self, database_path: Path) -> None:
        self.database_path = Path(database_path)
        self._ensure_schema()

    def _ensure_schema(self) -> None:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.database_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    subject TEXT,
                    sender TEXT,
                    recipients TEXT,
                    snippet TEXT,
                    body TEXT,
                    received_at TEXT,
                    thread_id TEXT,
                    metadata TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS attachments (
                    id TEXT,
                    message_id TEXT,
                    filename TEXT,
                    mime_type TEXT,
                    data BLOB,
                    metadata TEXT,
                    PRIMARY KEY (id, message_id),
                    FOREIGN KEY (message_id) REFERENCES messages(id)
                )
                """
            )

    def save_messages(self, messages: Iterable[Message]) -> None:
        with sqlite3.connect(self.database_path) as conn:
            for message in messages:
                conn.execute(
                    """
                    INSERT INTO messages (
                        id, subject, sender, recipients, snippet, body,
                        received_at, thread_id, metadata
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        subject=excluded.subject,
                        sender=excluded.sender,
                        recipients=excluded.recipients,
                        snippet=excluded.snippet,
                        body=excluded.body,
                        received_at=excluded.received_at,
                        thread_id=excluded.thread_id,
                        metadata=excluded.metadata
                    """,
                    (
                        message.id,
                        message.subject,
                        message.sender,
                        ",".join(message.recipients),
                        message.snippet,
                        message.body,
                        message.received_at.isoformat(),
                        message.thread_id,
                        str(message.metadata),
                    ),
                )
                for attachment in message.attachments:
                    self._save_attachment(conn, message.id, attachment)

    @staticmethod
    def _save_attachment(
        conn: sqlite3.Connection, message_id: str, attachment: Attachment
    ) -> None:
        conn.execute(
            """
            INSERT INTO attachments (
                id, message_id, filename, mime_type, data, metadata
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id, message_id) DO UPDATE SET
                filename=excluded.filename,
                mime_type=excluded.mime_type,
                data=excluded.data,
                metadata=excluded.metadata
            """,
            (
                attachment.id,
                message_id,
                attachment.filename,
                attachment.mime_type,
                attachment.data,
                str(attachment.metadata),
            ),
        )
