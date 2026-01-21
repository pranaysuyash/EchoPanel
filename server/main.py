from fastapi import FastAPI

from server.api.ws_asr import router as ws_asr_router

app = FastAPI()
app.include_router(ws_asr_router)
