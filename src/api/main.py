"""FastAPI application factory and entry point."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.api.config import get_settings
from src.api.routes import agents, health, pipeline
from src.utils.logger import configure_logging, get_logger

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    configure_logging(level=settings.log_level, fmt=settings.log_format)
    logger.info(
        "startup",
        app=settings.app_name,
        version=settings.app_version,
        env=settings.environment,
    )
    yield
    logger.info("shutdown", app=settings.app_name)


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=(
            "REST API for the DocuMagic data-processing pipeline. "
            "Provides endpoints to trigger pipeline runs, monitor status, "
            "and invoke individual AI agents."
        ),
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )

    app.include_router(health.router)
    app.include_router(pipeline.router)
    app.include_router(agents.router)

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn

    s = get_settings()
    uvicorn.run("src.api.main:app", host=s.host, port=s.port, reload=s.debug, workers=s.workers)
