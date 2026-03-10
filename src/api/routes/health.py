"""Health check routes."""

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import APIRouter, Depends

from src.api.config import Settings, get_settings
from src.api.models.schemas import HealthStatus

router = APIRouter(prefix="/health", tags=["health"])


def _check_aws(settings: Settings) -> str:
    """Verify connectivity to AWS S3."""
    try:
        s3 = boto3.client("s3", region_name=settings.aws_region)
        s3.head_bucket(Bucket=settings.s3_bucket_name)
        return "ok"
    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        if error_code in ("404", "NoSuchBucket"):
            return "bucket_not_found"
        return f"error: {error_code}"
    except BotoCoreError as exc:
        return f"error: {exc}"


@router.get("", response_model=HealthStatus, summary="Liveness probe")
async def health(settings: Settings = Depends(get_settings)) -> HealthStatus:
    """Return application liveness status."""
    return HealthStatus(
        status="ok",
        version=settings.app_version,
        environment=settings.environment,
    )


@router.get("/ready", response_model=HealthStatus, summary="Readiness probe")
async def ready(settings: Settings = Depends(get_settings)) -> HealthStatus:
    """Return application readiness status, including AWS dependency checks."""
    checks: dict[str, str] = {}
    checks["s3"] = _check_aws(settings)
    overall = "ok" if all(v == "ok" for v in checks.values()) else "degraded"
    return HealthStatus(
        status=overall,
        version=settings.app_version,
        environment=settings.environment,
        checks=checks,
    )
