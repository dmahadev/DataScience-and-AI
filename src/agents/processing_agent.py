"""Data processing agent – transforms raw data and writes results back to S3."""

from __future__ import annotations

import io
from typing import Any

import boto3
import pandas as pd
from botocore.exceptions import ClientError

from src.agents.base_agent import BaseAgent
from src.api.config import Settings
from src.utils.logger import get_logger

logger = get_logger(__name__)


class ProcessingAgent(BaseAgent):
    """Reads raw data from S3, applies transformations, and writes the result as Parquet."""

    agent_id = "processing"
    description = "Transforms raw data files from S3 and writes processed output as Parquet"
    capabilities = [
        "s3_read",
        "s3_write",
        "csv_to_parquet",
        "json_to_parquet",
        "deduplication",
        "schema_validation",
    ]

    def __init__(self, settings: Settings) -> None:
        super().__init__(settings)
        self._s3 = boto3.client("s3", region_name=settings.aws_region)

    # ------------------------------------------------------------------
    # BaseAgent implementation
    # ------------------------------------------------------------------

    async def _execute(self, input_data: dict[str, Any], **kwargs: Any) -> dict[str, Any]:
        """Process a raw data file and write the result to S3.

        Expected *input_data* keys:
        - ``source_key`` (str): S3 object key for the raw file.
        - ``destination_key`` (str): S3 object key for the output Parquet file.
        - ``format`` (str, optional): Source format – ``csv`` (default), ``json``, ``parquet``.
        - ``drop_duplicates`` (bool, optional): Remove duplicate rows (default: ``True``).
        - ``drop_na`` (bool, optional): Drop rows with null values (default: ``False``).
        """
        source_key: str = input_data["source_key"]
        destination_key: str = input_data["destination_key"]
        fmt: str = input_data.get("format", "csv")
        drop_duplicates: bool = input_data.get("drop_duplicates", True)
        drop_na: bool = input_data.get("drop_na", False)

        logger.info("processing_start", source_key=source_key, destination_key=destination_key)

        # --- Read ---
        df = self._read_from_s3(source_key, fmt)
        original_rows = len(df)

        # --- Transform ---
        df = self._transform(df, drop_duplicates=drop_duplicates, drop_na=drop_na)
        processed_rows = len(df)

        # --- Write ---
        size_bytes = self._write_to_s3(df, destination_key)

        logger.info(
            "processing_complete",
            source_key=source_key,
            destination_key=destination_key,
            original_rows=original_rows,
            processed_rows=processed_rows,
        )
        return {
            "source_key": source_key,
            "destination_key": destination_key,
            "original_rows": original_rows,
            "processed_rows": processed_rows,
            "output_size_bytes": size_bytes,
            "status": "processed",
        }

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _read_from_s3(self, key: str, fmt: str) -> pd.DataFrame:
        try:
            obj = self._s3.get_object(Bucket=self.settings.s3_bucket_name, Key=key)
            body = obj["Body"].read()
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            raise RuntimeError(f"Cannot read S3 object '{key}': {code}") from exc

        if fmt == "csv":
            return pd.read_csv(io.BytesIO(body))
        elif fmt == "json":
            return pd.read_json(io.BytesIO(body))
        elif fmt == "parquet":
            return pd.read_parquet(io.BytesIO(body))
        else:
            raise ValueError(f"Unsupported source format: '{fmt}'")

    @staticmethod
    def _transform(df: pd.DataFrame, *, drop_duplicates: bool, drop_na: bool) -> pd.DataFrame:
        if drop_duplicates:
            df = df.drop_duplicates()
        if drop_na:
            df = df.dropna()
        # Normalise column names to snake_case
        df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
        return df

    def _write_to_s3(self, df: pd.DataFrame, key: str) -> int:
        buf = io.BytesIO()
        df.to_parquet(buf, index=False)
        buf.seek(0)
        data = buf.read()
        try:
            self._s3.put_object(
                Bucket=self.settings.s3_bucket_name,
                Key=key,
                Body=data,
                ContentType="application/octet-stream",
            )
        except ClientError as exc:
            raise RuntimeError(f"Failed to write output to S3 '{key}'") from exc
        return len(data)
