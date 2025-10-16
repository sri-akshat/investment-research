"""Coordinators for running message ingestion pipelines."""
from __future__ import annotations

from typing import Iterable

from ..datastore import DataStore
from ..models import Message
from ..services.base import MessageService


def ingest_messages(service: MessageService, datastore: DataStore, query: str) -> None:
    """Fetch messages from the service and persist them into the datastore."""
    messages: Iterable[Message] = service.search(query)
    datastore.save_messages(messages)
