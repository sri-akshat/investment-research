"""CLI entry point for ingesting Gmail messages into a data store."""
from __future__ import annotations

import argparse
from pathlib import Path

from jarvis.messaging.datastore import SQLiteDataStore
from jarvis.messaging.pipelines.email_pipeline import ingest_messages
from jarvis.messaging.services.gmail_service import GmailService


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query", help="Gmail search query string")
    parser.add_argument(
        "--credentials",
        required=True,
        help="Path to Google OAuth client credentials JSON",
    )
    parser.add_argument(
        "--token",
        default=str(Path.home() / ".gmail-token.json"),
        help="Path to store the OAuth token JSON",
    )
    parser.add_argument(
        "--database",
        default="data/messages.db",
        help="SQLite database path for persisting results",
    )
    parser.add_argument(
        "--user-id",
        default="me",
        help="Gmail user id (default: me)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    service = GmailService(
        credentials_path=args.credentials,
        token_path=args.token,
        user_id=args.user_id,
    )
    datastore = SQLiteDataStore(Path(args.database))
    ingest_messages(service, datastore, args.query)


if __name__ == "__main__":
    main()
