"""Pydantic schemas for API request and response models."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------


class PipelineStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class DataFormat(str, Enum):
    CSV = "csv"
    JSON = "json"
    PARQUET = "parquet"
    TEXT = "text"


class AgentStatus(str, Enum):
    IDLE = "idle"
    BUSY = "busy"
    ERROR = "error"


# ---------------------------------------------------------------------------
# Pipeline schemas
# ---------------------------------------------------------------------------


class PipelineRunRequest(BaseModel):
    """Request body to trigger a new pipeline run."""

    name: str = Field(..., description="Human-readable name for this pipeline run")
    source_key: str = Field(..., description="S3 object key for the source data file")
    source_format: DataFormat = Field(DataFormat.CSV, description="Format of the source data")
    destination_key: str | None = Field(
        None, description="Optional S3 key for the output; auto-generated when omitted"
    )
    options: dict[str, Any] = Field(default_factory=dict, description="Additional pipeline options")


class PipelineRunResponse(BaseModel):
    """Response returned after triggering a pipeline run."""

    run_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    status: PipelineStatus = PipelineStatus.PENDING
    source_key: str
    destination_key: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    message: str = "Pipeline run queued successfully"


class PipelineRunStatus(BaseModel):
    """Current status of a pipeline run."""

    run_id: str
    name: str
    status: PipelineStatus
    created_at: datetime
    started_at: datetime | None = None
    completed_at: datetime | None = None
    error: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Agent schemas
# ---------------------------------------------------------------------------


class AgentInfo(BaseModel):
    """Metadata about a registered agent."""

    agent_id: str
    agent_type: str
    status: AgentStatus = AgentStatus.IDLE
    description: str = ""
    capabilities: list[str] = Field(default_factory=list)


class AgentInvokeRequest(BaseModel):
    """Request body for invoking an agent directly."""

    input_data: dict[str, Any] = Field(..., description="Payload forwarded to the agent")
    options: dict[str, Any] = Field(default_factory=dict, description="Agent-specific options")


class AgentInvokeResponse(BaseModel):
    """Response from an agent invocation."""

    agent_id: str
    status: AgentStatus
    output: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


# ---------------------------------------------------------------------------
# Health schemas
# ---------------------------------------------------------------------------


class HealthStatus(BaseModel):
    """Application health response."""

    status: str = "ok"
    version: str
    environment: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    checks: dict[str, str] = Field(default_factory=dict)
