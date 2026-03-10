"""AWS Bedrock agent – invokes foundation models for AI-powered analysis."""

from __future__ import annotations

import json
from typing import Any

import boto3
from botocore.exceptions import ClientError

from src.agents.base_agent import BaseAgent
from src.api.config import Settings
from src.utils.logger import get_logger

logger = get_logger(__name__)

# Default prompt template used when the caller does not supply one
_DEFAULT_PROMPT = (
    "You are a data analysis assistant. "
    "Analyse the following data and provide a concise summary with key insights:\n\n{data}"
)


class BedrockAgent(BaseAgent):
    """Invokes an AWS Bedrock foundation model to analyse processed data."""

    agent_id = "bedrock"
    description = "Invokes an AWS Bedrock foundation model for AI-powered data analysis"
    capabilities = ["text_generation", "data_analysis", "summarisation", "claude"]

    def __init__(self, settings: Settings) -> None:
        super().__init__(settings)
        self._client = boto3.client("bedrock-runtime", region_name=settings.aws_region)
        self._model_id = settings.bedrock_model_id
        self._max_tokens = settings.bedrock_max_tokens

    # ------------------------------------------------------------------
    # BaseAgent implementation
    # ------------------------------------------------------------------

    async def _execute(self, input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        """Send data to the Bedrock model and return the model response.

        Expected *input_data* keys:
        - ``data`` (str | dict): Data to analyse.  If a dict is supplied it is
          JSON-serialised before being included in the prompt.
        - ``prompt`` (str, optional): Custom prompt template.  Use ``{data}`` as a
          placeholder for the serialised *data*.
        - ``max_tokens`` (int, optional): Override the default token limit.
        """
        raw_data = input_data.get("data", "")
        if isinstance(raw_data, dict):
            raw_data = json.dumps(raw_data, indent=2, default=str)

        prompt_template: str = input_data.get("prompt", _DEFAULT_PROMPT)
        prompt = prompt_template.format(data=raw_data)
        max_tokens: int = int(input_data.get("max_tokens", self._max_tokens))

        logger.info("bedrock_invoke_start", model_id=self._model_id)

        response_text = self._invoke_model(prompt, max_tokens)

        logger.info("bedrock_invoke_complete", model_id=self._model_id)
        return {
            "model_id": self._model_id,
            "response": response_text,
            "status": "completed",
        }

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _invoke_model(self, prompt: str, max_tokens: int) -> str:
        """Call the Bedrock Claude model and return the assistant's reply."""
        body = json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": max_tokens,
                "messages": [{"role": "user", "content": prompt}],
            }
        )
        try:
            response = self._client.invoke_model(
                modelId=self._model_id,
                body=body,
                contentType="application/json",
                accept="application/json",
            )
            result = json.loads(response["body"].read())
            return result["content"][0]["text"]
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            logger.error("bedrock_invoke_failed", model_id=self._model_id, code=code)
            raise RuntimeError(f"Bedrock invocation failed [{code}]") from exc
