"""Pipeline step definitions for the DocuMagic data-processing pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class StepStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class StepResult:
    """Outcome of a single pipeline step."""

    step_name: str
    status: StepStatus
    output: dict[str, Any] = field(default_factory=dict)
    error: str | None = None


@dataclass
class PipelineStep:
    """Configuration for a single pipeline step."""

    name: str
    agent_id: str
    input_mapper: Any  # callable(context) -> dict
    required: bool = True


def build_default_pipeline(
    source_key: str,
    source_format: str,
    destination_key: str,
    run_id: str,
) -> list[PipelineStep]:
    """Return the ordered list of steps for a standard pipeline run.

    Steps:
    1. **ingest**  – validate and register the raw file.
    2. **process** – transform and persist as Parquet.
    3. **analyse** – run AI summarisation via Bedrock.
    """
    return [
        PipelineStep(
            name="ingest",
            agent_id="ingestion",
            input_mapper=lambda _ctx: {
                "source_key": source_key,
                "run_id": run_id,
                "format": source_format,
            },
        ),
        PipelineStep(
            name="process",
            agent_id="processing",
            input_mapper=lambda _ctx: {
                "source_key": source_key,
                "destination_key": destination_key,
                "format": source_format,
            },
        ),
        PipelineStep(
            name="analyse",
            agent_id="bedrock",
            input_mapper=lambda ctx: {
                "data": ctx.get("process", {}).get("output", {}),
            },
            required=False,  # Bedrock is optional; don't fail the run if unavailable
        ),
    ]
