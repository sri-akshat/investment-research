"""Messaging pipelines available to Jarvis."""

from .email_pipeline import ingest_messages

__all__ = ["ingest_messages"]
