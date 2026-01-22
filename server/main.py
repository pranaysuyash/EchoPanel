from fastapi import FastAPI

from server.api.ws_live_listener import router as ws_router

app = FastAPI()
app.include_router(ws_router)


@app.get("/")
async def root() -> dict:
    return {"status": "ok"}


from server.services.asr_providers import ASRProviderRegistry
from server.services.asr_stream import _get_default_config

@app.get("/health")
async def health_check() -> dict:
    try:
        config = _get_default_config()
        provider = ASRProviderRegistry.get_provider(config)
        if provider and provider.is_available:
            return {"status": "ok", "service": "echopanel", "model": provider.name}
        return {"status": "loading", "service": "echopanel"}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def main() -> None:
    import uvicorn

    uvicorn.run("server.main:app", host="127.0.0.1", port=8000, reload=False)


if __name__ == "__main__":
    main()

