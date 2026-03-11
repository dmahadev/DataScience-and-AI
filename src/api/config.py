"""Application configuration using pydantic-settings."""

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Application
    app_name: str = "DocuMagic Data Processing API"
    app_version: str = "1.0.0"
    environment: Literal["development", "staging", "production"] = "development"
    debug: bool = False

    # Server
    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 1

    # AWS
    aws_region: str = "us-west-2"
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""

    # S3
    s3_bucket_name: str = "DocuMagic-bucket"
    s3_raw_prefix: str = "raw/"
    s3_processed_prefix: str = "processed/"

    # DynamoDB
    dynamodb_table_name: str = "DocuMagic-table"

    # Bedrock
    bedrock_model_id: str = "anthropic.claude-3-sonnet-20240229-v1:0"
    bedrock_max_tokens: int = 4096

    # Step Functions
    step_function_arn: str = ""

    # Pipeline
    pipeline_max_workers: int = 4
    pipeline_batch_size: int = 100
    pipeline_timeout_seconds: int = 300

    # Logging
    log_level: str = "INFO"
    log_format: Literal["json", "text"] = "json"


@lru_cache
def get_settings() -> Settings:
    return Settings()
