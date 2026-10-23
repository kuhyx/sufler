"""The one error type of the assistant endpoints (explain, render_line)."""

from __future__ import annotations


class AssistError(Exception):
    """A request the PC cannot answer: an HTTP status and a reason for kuhy."""

    def __init__(self, status: int, message: str) -> None:
        """Keep both; `message` is what the app shows."""
        super().__init__(message)
        self.status = status
        self.message = message
