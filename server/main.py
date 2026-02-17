import asyncio
import logging
import os
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request

from server.api.documents import router as documents_router
from server.api.ws_live_listener import router as ws_router
from server.api.brain_dump_query import router as brain_dump_router
from server.services.asr_providers import ASRProviderRegistry
from server.services.asr_stream import _get_default_config
from server.security import extract_http_token, is_authorized

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
HF_TOKEN_ENV = "ECHOPANEL_HF_TOKEN"

def _load_local_dotenv_defaults() -> None:
    """
    Best-effort local `.env` loader for developer runs.

    - Does not override already-set environment variables.
    - Avoids adding a python-dotenv dependency.
    - Intended to make `python -m server.main` and scripts work when `.env` exists.
    """
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.is_file():
        return

    try:
        for raw in env_path.read_text(errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export ") :].strip()
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip()
            if not k or not v:
                continue
            # Strip a single layer of wrapping quotes.
            if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                v = v[1:-1]
            os.environ.setdefault(k, v)
    except Exception:
        # Deliberately silent: `.env` is optional and should not block startup.
        return


def _sync_huggingface_token_env() -> None:
    """
    If the user configured `ECHOPANEL_HF_TOKEN`, propagate it to the standard
    Hugging Face env vars so provider downloads (faster-whisper / hub) can
    benefit from authenticated/pro plans without requiring duplicate config.
    """
    token = os.getenv(HF_TOKEN_ENV, "").strip()
    if not token:
        return

    # Only fill if unset so explicit user configuration wins.
    os.environ.setdefault("HF_TOKEN", token)
    os.environ.setdefault("HUGGINGFACE_HUB_TOKEN", token)


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

    # Developer convenience: load `.env` if present (without overriding explicit env vars).
    _load_local_dotenv_defaults()

    # Ensure HF token is available for model downloads (if configured).
    _sync_huggingface_token_env()
    
    # Security: Warn if authentication is not configured in production
    from server.security import is_auth_required
    if not is_auth_required():
        env_mode = os.getenv("ECHOPANEL_ENV", "development").lower()
        if env_mode == "production":
            logger.error(
                "CRITICAL: ECHOPANEL_WS_AUTH_TOKEN is not configured in production mode. "
                "This exposes your personal audio memories to unauthorized access. "
                "Please set ECHOPANEL_WS_AUTH_TOKEN to a strong token before starting the server."
            )
            raise RuntimeError("Missing required authentication token in production mode")
        else:
            logger.warning(
                "Authentication is NOT configured (permissive mode). "
                "All endpoints are accessible without credentials. "
                "Set ECHOPANEL_WS_AUTH_TOKEN for security."
            )
    
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

    # QW-003: Preload embedding model for RAG
    try:
        from server.services.embeddings import get_embedding_service
        embedding_service = get_embedding_service()
        if embedding_service.is_available():
            # Warmup is lightweight, do it synchronously
            embedding_service.warmup()
            logger.info("Embedding model warmed up successfully")
        else:
            logger.warning("Embedding service not available (sentence-transformers not installed)")
    except Exception as e:
        logger.warning(f"Embedding model warmup failed: {e}")
        # Continue anyway - RAG will work without embeddings (lexical only)

    # Brain Dump: Initialize storage and indexing
    try:
        from server.services.brain_dump_indexer import initialize_indexer
        from server.services.brain_dump_integration import initialize_integration
        indexer = await initialize_indexer()
        initialize_integration(indexer)
        logger.info("Brain Dump indexer initialized")
    except Exception as e:
        logger.warning(f"Brain Dump initialization failed: {e}")
        # Continue anyway - core functionality works without brain dump

    # Rate Limiter: Initialize for API protection
    try:
        from server.api.rate_limiter import initialize_rate_limiter, RateLimitConfig
        config = RateLimitConfig(
            requests_per_minute=int(os.getenv("ECHOPANEL_RATE_LIMIT_PER_MINUTE", "60")),
            requests_per_hour=int(os.getenv("ECHOPANEL_RATE_LIMIT_PER_HOUR", "1000")),
            burst_size=int(os.getenv("ECHOPANEL_RATE_LIMIT_BURST", "10"))
        )
        await initialize_rate_limiter(config)
        logger.info(f"Rate limiter initialized: {config.requests_per_minute}/min, {config.requests_per_hour}/hour")
    except Exception as e:
        logger.warning(f"Rate limiter initialization failed: {e}")
        # Continue anyway - rate limiting is optional

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

    # Brain Dump: Shutdown indexer
    try:
        from server.services.brain_dump_indexer import shutdown_indexer
        from server.services.brain_dump_integration import shutdown_integration
        await shutdown_indexer()
        await shutdown_integration()
        logger.info("Brain Dump indexer shut down")
    except Exception as e:
        logger.warning(f"Brain Dump shutdown failed: {e}")

    # Rate Limiter: Shutdown
    try:
        from server.api.rate_limiter import shutdown_rate_limiter
        await shutdown_rate_limiter()
        logger.info("Rate limiter shut down")
    except Exception as e:
        logger.warning(f"Rate limiter shutdown failed: {e}")

    logger.info("Shutting down EchoPanel server...")


app = FastAPI(lifespan=lifespan)
app.include_router(ws_router)
app.include_router(documents_router)
app.include_router(brain_dump_router)


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    """Apply rate limiting to all HTTP requests."""
    from server.api.rate_limiter import get_rate_limiter
    
    # Skip rate limiting for health checks (used by monitoring)
    if request.url.path == "/health":
        return await call_next(request)
    
    # Skip rate limiting for test clients (TestClient uses "testclient" as host)
    if request.client and request.client.host == "testclient":
        return await call_next(request)
    
    # Get client identifier (IP address or token)
    client_id = request.client.host if request.client else "unknown"
    
    # Use auth token as client ID if available (per-user rate limiting)
    auth_token = _extract_token(request)
    if auth_token:
        client_id = f"token:{auth_token[:16]}"
    
    limiter = get_rate_limiter()
    if not await limiter.acquire(client_id):
        remaining = limiter.get_remaining(client_id)
        from fastapi.responses import JSONResponse
        return JSONResponse(
            status_code=429,
            content={
                "error": "rate_limit_exceeded",
                "message": "Too many requests. Please try again later.",
                "retry_after_minute": 60,
                "remaining": remaining
            },
            headers={
                "X-RateLimit-Remaining-Minute": str(remaining.get("minute", 0)),
                "X-RateLimit-Remaining-Hour": str(remaining.get("hour", 0)),
                "Retry-After": "60"
            }
        )
    
    response = await call_next(request)
    
    # Add rate limit headers to response
    remaining = limiter.get_remaining(client_id)
    response.headers["X-RateLimit-Remaining-Minute"] = str(remaining.get("minute", 0))
    response.headers["X-RateLimit-Remaining-Hour"] = str(remaining.get("hour", 0))
    
    return response


@app.get("/")
async def root(request: Request) -> dict:
    _require_http_auth(request)
    logger.info("Root endpoint accessed.")
    return {"status": "ok", "service": "echopanel"}


@app.get("/health")
async def health_check(request: Request) -> dict:
    _require_http_auth(request)
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
                "process_rss_mb": model_health.process_rss_mb,
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
async def get_capabilities(request: Request) -> dict:
    _require_http_auth(request)
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
async def get_model_status(request: Request) -> dict:
    _require_http_auth(request)
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
