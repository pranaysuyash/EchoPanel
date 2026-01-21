from fastapi import FastAPI

from server.api.ws_live_listener import router as ws_router

app = FastAPI()
app.include_router(ws_router)


@app.get("/")
async def health_check() -> dict:
    return {"status": "ok"}


def main() -> None:
    import uvicorn

    uvicorn.run("server.main:app", host="127.0.0.1", port=8000, reload=False)


if __name__ == "__main__":
    main()

