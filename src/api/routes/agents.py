"""Agents API routes – list and invoke registered agents."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from src.agents.bedrock_agent import BedrockAgent
from src.agents.ingestion_agent import IngestionAgent
from src.agents.processing_agent import ProcessingAgent
from src.api.config import Settings, get_settings
from src.api.models.schemas import AgentInfo, AgentInvokeRequest, AgentInvokeResponse, AgentStatus
from src.utils.logger import get_logger

router = APIRouter(prefix="/agents", tags=["agents"])
logger = get_logger(__name__)


def _build_registry(settings: Settings) -> dict[str, object]:
    return {
        "ingestion": IngestionAgent(settings),
        "processing": ProcessingAgent(settings),
        "bedrock": BedrockAgent(settings),
    }


@router.get("", response_model=list[AgentInfo], summary="List all registered agents")
async def list_agents(settings: Settings = Depends(get_settings)) -> list[AgentInfo]:
    """Return metadata for every registered agent."""
    registry = _build_registry(settings)
    return [agent.info() for agent in registry.values()]  # type: ignore[union-attr]


@router.post(
    "/{agent_id}/invoke",
    response_model=AgentInvokeResponse,
    summary="Invoke a specific agent",
)
async def invoke_agent(
    agent_id: str,
    body: AgentInvokeRequest,
    settings: Settings = Depends(get_settings),
) -> AgentInvokeResponse:
    """Invoke the named agent with the provided input data."""
    registry = _build_registry(settings)
    agent = registry.get(agent_id)
    if agent is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Agent '{agent_id}' not found. Available: {list(registry.keys())}",
        )
    logger.info("agent_invoked", agent_id=agent_id)
    try:
        output = await agent.run(body.input_data, **body.options)  # type: ignore[union-attr]
        return AgentInvokeResponse(
            agent_id=agent_id,
            status=AgentStatus.IDLE,
            output=output,
        )
    except Exception as exc:  # noqa: BLE001
        logger.error("agent_invocation_failed", agent_id=agent_id, error=str(exc))
        return AgentInvokeResponse(
            agent_id=agent_id,
            status=AgentStatus.ERROR,
            error=str(exc),
        )
