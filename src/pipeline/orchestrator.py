"""Pipeline orchestrator – coordinates agent execution for a pipeline run."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any

from src.agents.bedrock_agent import BedrockAgent
from src.agents.ingestion_agent import IngestionAgent
from src.agents.processing_agent import ProcessingAgent
from src.api.config import Settings
from src.api.models.schemas import PipelineStatus
from src.pipeline.steps import StepResult, StepStatus, build_default_pipeline
from src.utils.logger import get_logger

logger = get_logger(__name__)


class PipelineOrchestrator:
    """Coordinates the execution of all pipeline steps for a single run."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._agents = {
            "ingestion": IngestionAgent(settings),
            "processing": ProcessingAgent(settings),
            "bedrock": BedrockAgent(settings),
        }

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    async def run_async(
        self,
        *,
        run_id: str,
        source_key: str,
        source_format: str,
        destination_key: str,
        options: dict[str, Any],
        registry: dict[str, dict[str, Any]],
    ) -> None:
        """Execute the pipeline asynchronously and update *registry* in place."""
        asyncio.create_task(
            self._run(
                run_id=run_id,
                source_key=source_key,
                source_format=source_format,
                destination_key=destination_key,
                options=options,
                registry=registry,
            )
        )

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    async def _run(
        self,
        *,
        run_id: str,
        source_key: str,
        source_format: str,
        destination_key: str,
        options: dict[str, Any],
        registry: dict[str, dict[str, Any]],
    ) -> None:
        record = registry[run_id]
        record["status"] = PipelineStatus.RUNNING
        record["started_at"] = datetime.now(timezone.utc)

        steps = build_default_pipeline(
            source_key=source_key,
            source_format=source_format,
            destination_key=destination_key,
            run_id=run_id,
        )

        context: dict[str, Any] = {}
        step_results: list[StepResult] = []

        for step in steps:
            agent = self._agents.get(step.agent_id)
            if agent is None:
                step_results.append(
                    StepResult(step_name=step.name, status=StepStatus.SKIPPED)
                )
                continue

            try:
                input_data = step.input_mapper(context)
                logger.info("step_start", run_id=run_id, step=step.name)
                output = await agent.run(input_data)
                context[step.name] = {"output": output}
                step_results.append(
                    StepResult(step_name=step.name, status=StepStatus.COMPLETED, output=output)
                )
                logger.info("step_complete", run_id=run_id, step=step.name)
            except Exception as exc:  # noqa: BLE001
                logger.error("step_failed", run_id=run_id, step=step.name, error=str(exc))
                step_results.append(
                    StepResult(
                        step_name=step.name,
                        status=StepStatus.FAILED,
                        error=str(exc),
                    )
                )
                if step.required:
                    record["status"] = PipelineStatus.FAILED
                    record["error"] = f"Step '{step.name}' failed: {exc}"
                    record["completed_at"] = datetime.now(timezone.utc)
                    record["metadata"]["steps"] = [
                        {"name": r.step_name, "status": r.status, "error": r.error}
                        for r in step_results
                    ]
                    return

        record["status"] = PipelineStatus.COMPLETED
        record["completed_at"] = datetime.now(timezone.utc)
        record["metadata"]["steps"] = [
            {"name": r.step_name, "status": r.status} for r in step_results
        ]
        logger.info("pipeline_complete", run_id=run_id)
