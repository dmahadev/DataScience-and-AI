"""Structured logging helpers."""

from __future__ import annotations

import logging
import sys
from typing import Any, Literal

try:
    import structlog

    _STRUCTLOG_AVAILABLE = True
except ImportError:
    _STRUCTLOG_AVAILABLE = False


def configure_logging(
    level: str = "INFO",
    fmt: Literal["json", "text"] = "json",
) -> None:
    """Configure application-wide logging.

    Uses *structlog* for structured output when available; falls back to the
    standard library otherwise.
    """
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, level.upper(), logging.INFO),
    )

    if _STRUCTLOG_AVAILABLE:
        renderer = (
            structlog.processors.JSONRenderer()
            if fmt == "json"
            else structlog.dev.ConsoleRenderer()
        )
        structlog.configure(
            processors=[
                structlog.contextvars.merge_contextvars,
                structlog.processors.add_log_level,
                structlog.processors.TimeStamper(fmt="iso"),
                renderer,
            ],
            wrapper_class=structlog.make_filtering_bound_logger(
                getattr(logging, level.upper(), logging.INFO)
            ),
            context_class=dict,
            logger_factory=structlog.PrintLoggerFactory(),
        )


def get_logger(name: str) -> Any:
    """Return a logger for *name*.

    Returns a structlog bound logger when available, otherwise a standard
    :class:`logging.Logger`.
    """
    if _STRUCTLOG_AVAILABLE:
        return structlog.get_logger(name)
    return logging.getLogger(name)
