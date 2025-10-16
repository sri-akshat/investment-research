"""Provider integrations for Jarvis messaging ingestion."""

from .base import MessageService
from .gmail_service import GmailService

__all__ = ["MessageService", "GmailService"]
