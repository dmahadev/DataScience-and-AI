"""AWS utility helpers used across agents and pipeline steps."""

from __future__ import annotations

import json
from typing import Any

import boto3
from botocore.exceptions import ClientError

from src.utils.logger import get_logger

logger = get_logger(__name__)


def get_s3_client(region: str) -> Any:
    """Return a boto3 S3 client for *region*."""
    return boto3.client("s3", region_name=region)


def get_dynamodb_resource(region: str) -> Any:
    """Return a boto3 DynamoDB resource for *region*."""
    return boto3.resource("dynamodb", region_name=region)


def upload_bytes_to_s3(
    s3_client: Any,
    bucket: str,
    key: str,
    data: bytes,
    content_type: str = "application/octet-stream",
) -> None:
    """Upload *data* to *bucket*/*key* in S3."""
    try:
        s3_client.put_object(Bucket=bucket, Key=key, Body=data, ContentType=content_type)
        logger.info("s3_upload_success", bucket=bucket, key=key, bytes=len(data))
    except ClientError as exc:
        logger.error("s3_upload_failed", bucket=bucket, key=key, error=str(exc))
        raise


def download_bytes_from_s3(s3_client: Any, bucket: str, key: str) -> bytes:
    """Download and return the raw bytes of an S3 object."""
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        data: bytes = response["Body"].read()
        logger.info("s3_download_success", bucket=bucket, key=key, bytes=len(data))
        return data
    except ClientError as exc:
        logger.error("s3_download_failed", bucket=bucket, key=key, error=str(exc))
        raise


def put_dynamodb_item(table: Any, item: dict[str, Any]) -> None:
    """Write *item* to a DynamoDB *table* object."""
    try:
        table.put_item(Item=item)
        logger.info("dynamodb_put_success", item_id=item.get("id"))
    except ClientError as exc:
        logger.error("dynamodb_put_failed", error=str(exc))
        raise


def start_step_function(
    sfn_client: Any,
    state_machine_arn: str,
    name: str,
    input_data: dict[str, Any],
) -> str:
    """Start a Step Functions execution and return its ARN."""
    try:
        response = sfn_client.start_execution(
            stateMachineArn=state_machine_arn,
            name=name,
            input=json.dumps(input_data),
        )
        execution_arn: str = response["executionArn"]
        logger.info("sfn_execution_started", arn=execution_arn)
        return execution_arn
    except ClientError as exc:
        logger.error("sfn_start_failed", arn=state_machine_arn, error=str(exc))
        raise
