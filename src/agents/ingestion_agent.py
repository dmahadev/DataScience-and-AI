"""Data ingestion agent – reads raw data from S3 and stores metadata in DynamoDB."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

from src.agents.base_agent import BaseAgent
from src.api.config import Settings
from src.utils.logger import get_logger

logger = get_logger(__name__)


class IngestionAgent(BaseAgent):
    """Reads raw files from S3, validates them, and registers records in DynamoDB."""

    agent_id = "ingestion"
    description = "Ingests raw data files from S3 and registers them in DynamoDB"
    capabilities = ["s3_read", "dynamodb_write", "csv", "json", "parquet"]

    def __init__(self, settings: Settings) -> None:
        super().__init__(settings)
        self._s3 = boto3.client("s3", region_name=settings.aws_region)
        self._dynamo = boto3.resource("dynamodb", region_name=settings.aws_region)
        self._table = self._dynamo.Table(settings.dynamodb_table_name)

    # ------------------------------------------------------------------
    # BaseAgent implementation
    # ------------------------------------------------------------------

    async def _execute(self, input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        """Ingest a file from S3 and register a record in DynamoDB.

        Expected *input_data* keys:
        - ``source_key`` (str): S3 object key to ingest.
        - ``run_id`` (str, optional): Pipeline run ID.
        - ``format`` (str, optional): Data format hint (csv/json/parquet).
        """
        source_key: str = input_data["source_key"]
        run_id: str = input_data.get("run_id", str(uuid.uuid4()))
        fmt: str = input_data.get("format", "csv")

        logger.info("ingestion_start", run_id=run_id, source_key=source_key)

        # Fetch object metadata from S3 (avoids downloading the full file)
        metadata = self._get_s3_metadata(source_key)

        # Register the ingestion event in DynamoDB
        record = {
            "id": run_id,
            "source_key": source_key,
            "format": fmt,
            "size_bytes": metadata.get("ContentLength", 0),
            "content_type": metadata.get("ContentType", "application/octet-stream"),
            "ingested_at": datetime.now(timezone.utc).isoformat(),
            "status": "ingested",
        }
        self._put_dynamo_record(record)

        logger.info("ingestion_complete", run_id=run_id, size_bytes=record["size_bytes"])
        return {
            "run_id": run_id,
            "source_key": source_key,
            "size_bytes": record["size_bytes"],
            "status": "ingested",
        }

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _get_s3_metadata(self, key: str) -> dict[str, Any]:
        try:
            response = self._s3.head_object(Bucket=self.settings.s3_bucket_name, Key=key)
            return response
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            logger.error("s3_head_object_failed", key=key, code=code)
            raise RuntimeError(f"Cannot access S3 object '{key}': {code}") from exc

    def _put_dynamo_record(self, record: dict[str, Any]) -> None:
        try:
            self._table.put_item(Item=record)
        except ClientError as exc:
            logger.error("dynamodb_put_failed", error=str(exc))
            raise RuntimeError("Failed to write ingestion record to DynamoDB") from exc
