import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from server.api.ws_live_listener import router as ws_router
from server.services.asr_providers import ASRProviderRegistry
from server.services.asr_stream import _get_default_config

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle application startup and shutdown events."""
    logger.info("Starting EchoPanel server...")

    # Initialize ASR providers
    try:
        provider = ASRProviderRegistry.get_provider()
        if provider and provider.is_available:
            logger.info(f"ASR provider '{provider.name}' initialized successfully.")
        else:
            logger.warning("No ASR provider available. Some features may not work.")
    except Exception as e:
        logger.error(f"Failed to initialize ASR provider: {e}")
        # Don't raise here to allow server to start even if ASR fails

    yield

    logger.info("Shutting down EchoPanel server...")


app = FastAPI(lifespan=lifespan)
app.include_router(ws_router)


@app.get("/")
async def root() -> dict:
    logger.info("Root endpoint accessed.")
    return {"status": "ok", "service": "echopanel"}


@app.get("/health")
async def health_check() -> dict:
    """
    Health check that reflects ASR readiness.

    - Returns 200 only when an ASR provider is available.
    - Returns 503 with a reason when the server is up but can't transcribe.
    """
    logger.debug("Health check requested.")

    try:
        config = _get_default_config()
        provider = ASRProviderRegistry.get_provider(config=config)
        provider_name = provider.name if provider else None

        if provider and provider.is_available:
            return {
                "status": "ok",
                "service": "echopanel",
                "provider": provider_name,
                "model": config.model_name,
            }

        raise HTTPException(
            status_code=503,
            detail={
                "status": "loading",
                "service": "echopanel",
                "provider": provider_name,
                "model": config.model_name,
                "reason": "ASR provider not available (missing deps or still loading)",
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail={"status": "error", "service": "echopanel", "error": str(e)})


def main() -> None:
    import uvicorn

    uvicorn.run("server.main:app", host="127.0.0.1", port=8000, reload=False)


if __name__ == "__main__":
    main()
