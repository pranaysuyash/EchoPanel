#!/usr/bin/env python3
"""
Run a small, end-user-aligned streaming model matrix against the local server.

What this measures:
- Startup warmup time + RSS via /health
- Realtime-paced streaming for N seconds from a WAV file
- WS metrics: queue_fill_ratio, dropped_recent/total, avg_infer_ms, realtime_factor
- ASR event counts

It starts/stops uvicorn per model so results include warmup behavior.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import signal
import subprocess
import sys
import time
import wave
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.request import Request, urlopen

import websockets


PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _http_get_json(url: str, timeout_s: float = 2.0) -> dict:
    req = Request(url, method="GET")
    with urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))


def _wait_for_health(base_url: str, deadline_s: float) -> Tuple[bool, Optional[dict], Optional[str]]:
    """
    Wait for /health to return 200 and JSON.
    Returns (ok, payload, last_error).
    """
    last_err: Optional[str] = None
    while time.time() < deadline_s:
        try:
            payload = _http_get_json(f"{base_url}/health", timeout_s=2.0)
            if payload.get("status") == "ok":
                return True, payload, None
        except Exception as e:
            last_err = repr(e)
        time.sleep(0.5)
    return False, None, last_err


@dataclass
class StreamingSummary:
    model: str
    provider: str
    chunk_seconds: int
    vad_enabled: bool
    health: Optional[dict]
    ws_statuses: List[Tuple[str, str]]
    asr_partials: int
    asr_finals: int
    metrics_samples: int
    metrics_max_queue_fill_ratio: float
    metrics_max_dropped_recent: int
    metrics_last_realtime_factor: float
    metrics_avg_realtime_factor: float
    metrics_avg_infer_ms: float
    error: Optional[str] = None


async def _stream_realtime(
    ws_url: str,
    wav_path: Path,
    seconds: float,
    chunk_seconds: float,
    source: str = "system",
) -> Tuple[List[Tuple[str, str]], int, int, List[dict]]:
    statuses: List[Tuple[str, str]] = []
    partials = 0
    finals = 0
    metrics: List[dict] = []

    session_id = f"matrix_{int(time.time())}"

    async with websockets.connect(ws_url, ping_interval=20, ping_timeout=20, max_size=2**24) as ws:
        await ws.send(
            json.dumps(
                {
                    "type": "start",
                    "session_id": session_id,
                    "sample_rate": 16000,
                    "format": "pcm_s16le",
                    "channels": 1,
                }
            )
        )

        async def recv_loop():
            nonlocal partials, finals
            try:
                while True:
                    msg = await ws.recv()
                    try:
                        data = json.loads(msg)
                    except Exception:
                        continue
                    t = data.get("type")
                    if t == "status":
                        statuses.append((str(data.get("state", "")), str(data.get("message", ""))[:160]))
                    elif t == "asr_partial":
                        partials += 1
                    elif t == "asr_final":
                        finals += 1
                    elif t == "metrics":
                        metrics.append(data)
            except Exception:
                return

        r = asyncio.create_task(recv_loop())

        # Send audio at realtime pace.
        frames_per_chunk = int(16000 * chunk_seconds)
        t0 = time.time()
        with wave.open(str(wav_path), "rb") as f:
            if f.getframerate() != 16000 or f.getnchannels() != 1 or f.getsampwidth() != 2:
                raise RuntimeError("WAV must be PCM16 mono 16kHz")

            while time.time() - t0 < seconds:
                chunk = f.readframes(frames_per_chunk)
                if not chunk:
                    break
                await ws.send(
                    json.dumps(
                        {"type": "audio", "data": base64.b64encode(chunk).decode("utf-8"), "source": source}
                    )
                )
                await asyncio.sleep(chunk_seconds)

        await ws.send(json.dumps({"type": "stop"}))
        await asyncio.sleep(2.0)
        r.cancel()

    return statuses, partials, finals, metrics


def _start_server(env: Dict[str, str], log_path: Path) -> subprocess.Popen:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    f = open(log_path, "wb")
    return subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "server.main:app", "--host", "127.0.0.1", "--port", "8000"],
        cwd=str(PROJECT_ROOT),
        env=env,
        stdout=f,
        stderr=subprocess.STDOUT,
        preexec_fn=None,
    )


def _stop_server(proc: subprocess.Popen) -> None:
    try:
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=5)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def _summarize_metrics(samples: List[dict]) -> Tuple[int, float, int, float, float, float]:
    if not samples:
        return 0, 0.0, 0, 0.0, 0.0, 0.0

    qfills = [float(s.get("queue_fill_ratio", 0.0) or 0.0) for s in samples]
    dropped_recent = [int(s.get("dropped_recent", 0) or 0) for s in samples]
    rtf = [float(s.get("realtime_factor", 0.0) or 0.0) for s in samples]
    infer_ms = [float(s.get("avg_infer_ms", 0.0) or 0.0) for s in samples]

    n = len(samples)
    return (
        n,
        max(qfills) if qfills else 0.0,
        max(dropped_recent) if dropped_recent else 0,
        float(rtf[-1]) if rtf else 0.0,
        sum(rtf) / max(1, len(rtf)),
        sum(infer_ms) / max(1, len(infer_ms)),
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio", type=Path, required=True)
    ap.add_argument("--models", nargs="+", required=True)
    ap.add_argument("--seconds", type=float, default=30.0)
    ap.add_argument("--chunk-seconds", type=float, default=0.04)
    ap.add_argument("--asr-chunk-seconds", type=int, default=2)
    ap.add_argument("--vad", type=int, default=1)
    ap.add_argument("--out-dir", type=Path, default=PROJECT_ROOT / "output" / "asr_matrix")
    args = ap.parse_args()

    out_dir = args.out_dir / time.strftime("%Y%m%d-%H%M%S")
    out_dir.mkdir(parents=True, exist_ok=True)

    results: List[StreamingSummary] = []

    for model in args.models:
        # Clean env: ensure local imports work, and avoid accidental auth gating.
        env = dict(os.environ)
        env["PYTHONPATH"] = "."
        env.pop("ECHOPANEL_WS_AUTH_TOKEN", None)

        env["ECHOPANEL_ASR_PROVIDER"] = "faster_whisper"
        env["ECHOPANEL_WHISPER_MODEL"] = model
        env["ECHOPANEL_WHISPER_DEVICE"] = "cpu"
        env["ECHOPANEL_WHISPER_COMPUTE"] = "int8"
        env["ECHOPANEL_ASR_CHUNK_SECONDS"] = str(args.asr_chunk_seconds)
        env["ECHOPANEL_ASR_VAD"] = "1" if args.vad else "0"
        env["ECHOPANEL_WHISPER_LANGUAGE"] = "en"
        env.setdefault("ECHOPANEL_AUTO_SELECT_VOXTRAL", "0")

        log_path = out_dir / f"server-{model.replace('/','_')}.log"
        proc = _start_server(env=env, log_path=log_path)

        try:
            ok, health, err = _wait_for_health("http://127.0.0.1:8000", deadline_s=time.time() + 120.0)
            if not ok:
                results.append(
                    StreamingSummary(
                        model=model,
                        provider="faster_whisper",
                        chunk_seconds=args.asr_chunk_seconds,
                        vad_enabled=bool(args.vad),
                        health=None,
                        ws_statuses=[],
                        asr_partials=0,
                        asr_finals=0,
                        metrics_samples=0,
                        metrics_max_queue_fill_ratio=0.0,
                        metrics_max_dropped_recent=0,
                        metrics_last_realtime_factor=0.0,
                        metrics_avg_realtime_factor=0.0,
                        metrics_avg_infer_ms=0.0,
                        error=f"server_not_ready: {err}",
                    )
                )
                continue

            try:
                statuses, partials, finals, metrics = asyncio.run(
                    _stream_realtime(
                        ws_url="ws://127.0.0.1:8000/ws/live-listener",
                        wav_path=args.audio,
                        seconds=args.seconds,
                        chunk_seconds=args.chunk_seconds,
                    )
                )
                (
                    n,
                    max_qfill,
                    max_drop_recent,
                    last_rtf,
                    avg_rtf,
                    avg_infer_ms,
                ) = _summarize_metrics(metrics)
                results.append(
                    StreamingSummary(
                        model=model,
                        provider="faster_whisper",
                        chunk_seconds=args.asr_chunk_seconds,
                        vad_enabled=bool(args.vad),
                        health=health,
                        ws_statuses=statuses[:20],
                        asr_partials=partials,
                        asr_finals=finals,
                        metrics_samples=n,
                        metrics_max_queue_fill_ratio=max_qfill,
                        metrics_max_dropped_recent=max_drop_recent,
                        metrics_last_realtime_factor=last_rtf,
                        metrics_avg_realtime_factor=avg_rtf,
                        metrics_avg_infer_ms=avg_infer_ms,
                        error=None,
                    )
                )
            except Exception as e:
                results.append(
                    StreamingSummary(
                        model=model,
                        provider="faster_whisper",
                        chunk_seconds=args.asr_chunk_seconds,
                        vad_enabled=bool(args.vad),
                        health=health,
                        ws_statuses=[],
                        asr_partials=0,
                        asr_finals=0,
                        metrics_samples=0,
                        metrics_max_queue_fill_ratio=0.0,
                        metrics_max_dropped_recent=0,
                        metrics_last_realtime_factor=0.0,
                        metrics_avg_realtime_factor=0.0,
                        metrics_avg_infer_ms=0.0,
                        error=repr(e),
                    )
                )
        finally:
            _stop_server(proc)

    out_json = out_dir / "results.json"
    out_json.write_text(json.dumps([asdict(r) for r in results], indent=2), encoding="utf-8")
    print(f"Wrote {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

