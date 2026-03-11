"""Pipeline API routes – trigger, monitor, and manage pipeline runs."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status

from src.api.config import Settings, get_settings
from src.api.models.schemas import (
    PipelineRunRequest,
    PipelineRunResponse,
    PipelineRunStatus,
    PipelineStatus,
)
from src.pipeline.orchestrator import PipelineOrchestrator
from src.utils.logger import get_logger

router = APIRouter(prefix="/pipeline", tags=["pipeline"])
logger = get_logger(__name__)

# In-memory run registry (replace with DynamoDB in production)
_run_registry: dict[str, dict[str, Any]] = {}


def _get_orchestrator(settings: Settings = Depends(get_settings)) -> PipelineOrchestrator:
    return PipelineOrchestrator(settings)


@router.post(
    "/runs",
    response_model=PipelineRunResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Trigger a new pipeline run",
)
async def create_run(
    body: PipelineRunRequest,
    orchestrator: PipelineOrchestrator = Depends(_get_orchestrator),
    settings: Settings = Depends(get_settings),
) -> PipelineRunResponse:
    """Accept a pipeline run request, queue it, and return the run metadata."""
    run_id = str(uuid.uuid4())
    destination_key = body.destination_key or (
        f"{settings.s3_processed_prefix}{run_id}/output.parquet"
    )

    run_record: dict[str, Any] = {
        "run_id": run_id,
        "name": body.name,
        "status": PipelineStatus.PENDING,
        "source_key": body.source_key,
        "destination_key": destination_key,
        "created_at": datetime.now(timezone.utc),
        "started_at": None,
        "completed_at": None,
        "error": None,
        "metadata": {},
    }
    _run_registry[run_id] = run_record

    logger.info("pipeline_run_queued", run_id=run_id, name=body.name)

    # Kick off the pipeline asynchronously (non-blocking)
    try:
        await orchestrator.run_async(
            run_id=run_id,
            source_key=body.source_key,
            source_format=body.source_format,
            destination_key=destination_key,
            options=body.options,
            registry=_run_registry,
        )
    except Exception as exc:  # noqa: BLE001
        logger.error("pipeline_run_start_failed", run_id=run_id, error=str(exc))
        run_record["status"] = PipelineStatus.FAILED
        run_record["error"] = str(exc)

    return PipelineRunResponse(
        run_id=run_id,
        name=body.name,
        status=run_record["status"],
        source_key=body.source_key,
        destination_key=destination_key,
        created_at=run_record["created_at"],
    )


@router.get(
    "/runs/{run_id}",
    response_model=PipelineRunStatus,
    summary="Get the status of a pipeline run",
)
async def get_run_status(run_id: str) -> PipelineRunStatus:
    """Return the current status of a pipeline run."""
    record = _run_registry.get(run_id)
    if record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Pipeline run '{run_id}' not found",
        )
    return PipelineRunStatus(**record)


@router.get(
    "/runs",
    response_model=list[PipelineRunStatus],
    summary="List all pipeline runs",
)
async def list_runs() -> list[PipelineRunStatus]:
    """Return a list of all known pipeline runs."""
    return [PipelineRunStatus(**r) for r in _run_registry.values()]


@router.delete(
    "/runs/{run_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Cancel a pending pipeline run",
)
async def cancel_run(run_id: str) -> None:
    """Cancel a pipeline run that has not yet completed."""
    record = _run_registry.get(run_id)
    if record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Pipeline run '{run_id}' not found",
        )
    if record["status"] not in (PipelineStatus.PENDING, PipelineStatus.RUNNING):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Cannot cancel a run with status '{record['status']}'",
        )
    record["status"] = PipelineStatus.CANCELLED
    logger.info("pipeline_run_cancelled", run_id=run_id)
