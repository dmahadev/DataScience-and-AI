"""Standalone agent worker process.

Runs as a long-lived process inside the Kubernetes Agents Deployment.
In a production system this would consume messages from an SQS queue or
similar and dispatch them to the appropriate agent.  This module provides
a minimal polling loop suitable for local development and demonstration.
"""

from __future__ import annotations

import asyncio
import signal
import sys
from typing import Any

from src.api.config import get_settings
from src.agents.ingestion_agent import IngestionAgent
from src.agents.processing_agent import ProcessingAgent
from src.agents.bedrock_agent import BedrockAgent
from src.utils.logger import configure_logging, get_logger

logger = get_logger(__name__)

_RUNNING = True


def _handle_shutdown(signum: int, frame: Any) -> None:
    global _RUNNING
    logger.info("worker_shutdown_signal", signum=signum)
    _RUNNING = False


async def _poll_loop(settings: Any) -> None:
    """Main agent polling loop.

    Replace the placeholder sleep with a real queue consumer
    (e.g. ``boto3`` SQS ``receive_message``) in production.
    """
    agents = {
        "ingestion": IngestionAgent(settings),
        "processing": ProcessingAgent(settings),
        "bedrock": BedrockAgent(settings),
    }
    logger.info("worker_started", agents=list(agents.keys()))

    while _RUNNING:
        # TODO: Replace with SQS long-poll or other message-queue consumer.
        await asyncio.sleep(5)

    logger.info("worker_stopped")


def main() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level, fmt=settings.log_format)

    signal.signal(signal.SIGTERM, _handle_shutdown)
    signal.signal(signal.SIGINT, _handle_shutdown)

    asyncio.run(_poll_loop(settings))


if __name__ == "__main__":
    main()
