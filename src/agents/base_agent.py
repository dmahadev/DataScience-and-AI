"""Abstract base class shared by all pipeline agents."""

from __future__ import annotations

import abc
from typing import Any

from src.api.config import Settings
from src.api.models.schemas import AgentInfo, AgentStatus


class BaseAgent(abc.ABC):
    """All pipeline agents inherit from this class."""

    #: Unique identifier used in API routing (override in subclasses)
    agent_id: str = ""
    #: Short human-readable description
    description: str = ""
    #: List of capabilities this agent advertises
    capabilities: list[str] = []

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._status = AgentStatus.IDLE

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def info(self) -> AgentInfo:
        """Return agent metadata for the /agents listing endpoint."""
        return AgentInfo(
            agent_id=self.agent_id,
            agent_type=type(self).__name__,
            status=self._status,
            description=self.description,
            capabilities=list(self.capabilities),
        )

    async def run(self, input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        """Execute the agent and return a result dict.

        Wraps :meth:`_execute` with status bookkeeping.
        """
        self._status = AgentStatus.BUSY
        try:
            result = await self._execute(input_data, **kwargs)
            self._status = AgentStatus.IDLE
            return result
        except Exception:
            self._status = AgentStatus.ERROR
            raise

    # ------------------------------------------------------------------
    # Template method – implement in subclasses
    # ------------------------------------------------------------------

    @abc.abstractmethod
    async def _execute(self, input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        """Agent-specific processing logic."""
