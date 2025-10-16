"""Service abstractions for message providers."""
from __future__ import annotations

import abc
from typing import Iterable

from ..models import Message


class MessageService(abc.ABC):
    """Abstract base class for message provider clients."""

    @abc.abstractmethod
    def search(self, query: str) -> Iterable[Message]:
        """Return messages matching the provider specific query."""
        raise NotImplementedError
