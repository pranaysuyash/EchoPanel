import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from server.api.documents import router as documents_router
from server.api.ws_live_listener import router as ws_router
from server.services.asr_providers import ASRProviderRegistry
from server.services.asr_stream import _get_default_config

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _env_flag(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() not in {"0", "false", "no", "off"}


def _prefer_whisper_cpp_for_apple_silicon(detector, profile, recommendation):
    if not _env_flag("ECHOPANEL_PREFER_WHISPER_CPP", default=True):
        return recommendation
    if recommendation.provider == "whisper_cpp":
        return recommendation
    if not getattr(profile, "has_mps", False):
        return recommendation

    try:
        whisper_available = detector._whisper_cpp_available()  # intentional use of detector probe
    except Exception as exc:  # pragma: no cover - defensive guard
        logger.warning("whisper.cpp availability check failed: %s", exc)
        return recommendation

    if not whisper_available:
        return recommendation

    model = "medium.en" if getattr(profile, "ram_gb", 0.0) >= 16 else "small.en"
    recommendation.provider = "whisper_cpp"
    recommendation.model = model
    recommendation.chunk_seconds = 2
    recommendation.compute_type = "q5_0"
    recommendation.device = "gpu"
    recommendation.vad_enabled = True
    recommendation.reason = f"{recommendation.reason}; preferred whisper_cpp on Apple Silicon"
    return recommendation


def _auto_select_provider():
    """Auto-select optimal ASR provider based on machine capabilities.
    
    TCK-20260211-009: Capability Detection + Auto-Provider Selection
    Only runs if ECHOPANEL_ASR_PROVIDER is not explicitly set.
    """
    # Skip if user explicitly set provider
    if os.getenv("ECHOPANEL_ASR_PROVIDER"):
        logger.info(f"Using user-specified provider: {os.getenv('ECHOPANEL_ASR_PROVIDER')}")
        return
    
    try:
        from server.services.capability_detector import CapabilityDetector
        
        logger.info("Auto-detecting optimal ASR provider...")
        detector = CapabilityDetector()
        profile = detector.detect()
        recommendation = detector.recommend(profile)
        recommendation = _prefer_whisper_cpp_for_apple_silicon(detector, profile, recommendation)
        
        # Set environment variables for the recommendation
        os.environ["ECHOPANEL_ASR_PROVIDER"] = recommendation.provider
        os.environ["ECHOPANEL_WHISPER_MODEL"] = recommendation.model
        os.environ["ECHOPANEL_ASR_CHUNK_SECONDS"] = str(recommendation.chunk_seconds)
        os.environ["ECHOPANEL_WHISPER_COMPUTE"] = recommendation.compute_type
        os.environ["ECHOPANEL_WHISPER_DEVICE"] = recommendation.device
        os.environ["ECHOPANEL_ASR_VAD"] = "1" if recommendation.vad_enabled else "0"
        
        logger.info(f"Auto-selected: {recommendation.provider}/{recommendation.model}")
        logger.info(f"  Reason: {recommendation.reason}")
        logger.info(f"  Hardware: {profile.ram_gb:.1f}GB RAM, {profile.cpu_cores} cores, "
                   f"MPS={profile.has_mps}, CUDA={profile.has_cuda}")
        
        if recommendation.fallback:
            logger.info(f"  Fallback: {recommendation.fallback.provider}/{recommendation.fallback.model}")
        
    except Exception as e:
        logger.warning(f"Provider auto-detection failed: {e}. Using defaults.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle application startup and shutdown events."""
    logger.info("Starting EchoPanel server...")
    
    # TCK-20260211-009: Auto-select provider based on capabilities
    _auto_select_provider()
    
    # PR4: Initialize model with warmup (eager loading)
    try:
        from server.services.model_preloader import initialize_model_at_startup
        model_ready = await initialize_model_at_startup()
        if not model_ready:
            logger.warning("Model warmup incomplete, first request may be slower")
    except Exception as e:
        logger.error(f"Model preloading failed: {e}")
        # Continue anyway - will load on first request

    diarization_prewarm_task: asyncio.Task[bool] | None = None
    if _env_flag("ECHOPANEL_PREWARM_DIARIZATION", default=True):
        try:
            from server.services.diarization import prewarm_diarization_pipeline

            timeout_seconds = float(os.getenv("ECHOPANEL_DIARIZATION_PREWARM_TIMEOUT", "120"))
            diarization_prewarm_task = asyncio.create_task(
                prewarm_diarization_pipeline(timeout_seconds=timeout_seconds)
            )
        except Exception as e:
            logger.warning(f"Failed to start diarization prewarm task: {e}")

    # Initialize ASR providers (legacy check)
    try:
        provider = ASRProviderRegistry.get_provider()
        if provider and provider.is_available:
            logger.info(f"ASR provider '{provider.name}' available.")
        else:
            logger.warning("No ASR provider available. Some features may not work.")
    except Exception as e:
        logger.error(f"Failed to initialize ASR provider: {e}")
        # Don't raise here to allow server to start even if ASR fails

    yield

    if diarization_prewarm_task and not diarization_prewarm_task.done():
        diarization_prewarm_task.cancel()
        try:
            await diarization_prewarm_task
        except asyncio.CancelledError:
            pass

    try:
        from server.services.model_preloader import shutdown_model_manager
        unloaded = await shutdown_model_manager()
        if not unloaded:
            logger.warning("Model shutdown did not complete cleanly")
    except Exception as e:
        logger.error(f"Model shutdown failed: {e}")

    logger.info("Shutting down EchoPanel server...")


app = FastAPI(lifespan=lifespan)
app.include_router(ws_router)
app.include_router(documents_router)


@app.get("/")
async def root() -> dict:
    logger.info("Root endpoint accessed.")
    return {"status": "ok", "service": "echopanel"}


@app.get("/health")
async def health_check() -> dict:
    """
    Health check that reflects ASR readiness.

    - Returns 200 only when an ASR provider is available and model is warmed up.
    - Returns 503 with a reason when the server is up but can't transcribe.
    """
    logger.debug("Health check requested.")

    try:
        config = _get_default_config()
        provider = ASRProviderRegistry.get_provider(config=config)
        provider_name = provider.name if provider else None
        
        # PR4: Check model preloader status
        from server.services.model_preloader import get_model_manager
        manager = get_model_manager()
        model_health = manager.health()
        
        # Deep health: provider must be available AND model warmed up
        if provider and provider.is_available and model_health.ready:
            return {
                "status": "ok",
                "service": "echopanel",
                "provider": provider_name,
                "model": config.model_name,
                "model_ready": True,
                "model_state": model_health.state.name,
                "load_time_ms": model_health.load_time_ms,
                "warmup_time_ms": model_health.warmup_time_ms,
            }
        
        # Not ready - determine why
        if not model_health.ready:
            reason = f"Model {model_health.state.name.lower()}"
            if model_health.last_error:
                reason += f": {model_health.last_error}"
        else:
            reason = "ASR provider not available"
        
        raise HTTPException(
            status_code=503,
            detail={
                "status": "loading",
                "service": "echopanel",
                "provider": provider_name,
                "model": config.model_name,
                "model_state": model_health.state.name,
                "reason": reason,
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail={"status": "error", "service": "echopanel", "error": str(e)})


@app.get("/capabilities")
async def get_capabilities() -> dict:
    """
    Get machine capabilities and ASR recommendations.
    
    TCK-20260211-009: Exposes capability detection to clients.
    """
    try:
        from server.services.capability_detector import get_optimal_config
        return get_optimal_config()
    except Exception as e:
        logger.error(f"Failed to get capabilities: {e}")
        raise HTTPException(
            status_code=500,
            detail={"status": "error", "message": str(e)}
        )


@app.get("/model-status")
async def get_model_status() -> dict:
    """
    Get model preloader status and statistics.
    
    PR4: Exposes model warmup status to clients.
    """
    try:
        from server.services.model_preloader import get_model_manager
        manager = get_model_manager()
        
        return {
            "status": "ok",
            "health": manager.health().to_dict(),
            "stats": manager.get_stats(),
        }
    except Exception as e:
        logger.error(f"Failed to get model status: {e}")
        raise HTTPException(
            status_code=500,
            detail={"status": "error", "message": str(e)}
        )


def main() -> None:
    import uvicorn

    uvicorn.run("server.main:app", host="127.0.0.1", port=8000, reload=False)


if __name__ == "__main__":
    main()
