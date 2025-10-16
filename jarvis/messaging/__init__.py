"""Messaging ingestion package for the Jarvis project."""

from .models import Attachment, Message
from .datastore import DataStore, SQLiteDataStore
from .pipelines.email_pipeline import ingest_messages

__all__ = [
    "Attachment",
    "Message",
    "DataStore",
    "SQLiteDataStore",
    "ingest_messages",
]
