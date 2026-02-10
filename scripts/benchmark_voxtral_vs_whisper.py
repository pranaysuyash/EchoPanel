#!/usr/bin/env python3
"""
benchmark_voxtral_vs_whisper.py — Head-to-head ASR comparison (local only)

Tests Faster-Whisper (local) vs Voxtral Realtime via voxtral.c (local, MPS).
Measures: load time, transcription time, RTF, and output quality.

Usage:
    python scripts/benchmark_voxtral_vs_whisper.py [audio.wav]

Requires:
    - faster-whisper + numpy (pip install faster-whisper numpy)
    - voxtral.c binary + model (see ../voxtral.c/)
"""

import json
import os
import subprocess
import sys
import time
import wave
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = PROJECT_ROOT / "output" / "asr_benchmark"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

AUDIO_PATH = sys.argv[1] if len(sys.argv) > 1 else str(PROJECT_ROOT / "test_speech.wav")
VOXTRAL_BIN = Path(os.getenv("ECHOPANEL_VOXTRAL_BIN", str(PROJECT_ROOT.parent / "voxtral.c" / "voxtral")))
VOXTRAL_MODEL = Path(os.getenv("ECHOPANEL_VOXTRAL_MODEL", str(PROJECT_ROOT.parent / "voxtral.c" / "voxtral-model")))


def get_audio_duration(path: str) -> float:
    with wave.open(path, "rb") as wf:
        return wf.getnframes() / wf.getframerate()


def test_faster_whisper(audio_path: str, model_name: str = "base.en") -> dict:
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        return {"error": "faster-whisper not installed"}

    result = {
        "provider": "faster_whisper",
        "model": model_name,
        "device": "cpu",
        "compute": "int8",
    }

    t0 = time.perf_counter()
    model = WhisperModel(model_name, device="cpu", compute_type="int8")
    result["load_time_s"] = round(time.perf_counter() - t0, 3)

    t0 = time.perf_counter()
    segments, info = model.transcribe(audio_path, language="en")
    segments = list(segments)
    result["transcribe_time_s"] = round(time.perf_counter() - t0, 3)

    result["transcript"] = " ".join(s.text.strip() for s in segments if s.text.strip())
    result["num_segments"] = len(segments)
    result["audio_duration_s"] = round(get_audio_duration(audio_path), 3)
    result["rtf"] = round(result["transcribe_time_s"] / result["audio_duration_s"], 3)

    return result


def test_voxtral_local(audio_path: str) -> dict:
    if not VOXTRAL_BIN.is_file():
        return {"error": f"voxtral.c binary not found at {VOXTRAL_BIN}"}
    if not (VOXTRAL_MODEL / "consolidated.safetensors").is_file():
        return {"error": f"Voxtral model not found at {VOXTRAL_MODEL}"}

    result = {
        "provider": "voxtral_local",
        "model": "Voxtral-Mini-4B-Realtime-2602",
        "device": "mps",
        "compute": "bf16",
    }

    t0 = time.perf_counter()
    proc = subprocess.run(
        [str(VOXTRAL_BIN), "-d", str(VOXTRAL_MODEL), "-i", audio_path],
        capture_output=True, text=True,
    )
    total_time = time.perf_counter() - t0

    if proc.returncode != 0:
        result["error"] = proc.stderr[:200]
        return result

    lines = proc.stdout.strip().splitlines()
    result["transcript"] = lines[0] if lines else ""

    stderr = proc.stderr
    import re
    enc_match = re.search(r"Encoder:.*\((\d+) ms\)", stderr)
    dec_match = re.search(r"Decoder:.*in (\d+) ms \(prefill (\d+) ms \+ ([\d.]+) ms/step\)", stderr)
    load_match = re.search(r"Metal GPU: ([\d.]+) MB", stderr)

    enc_ms = int(enc_match.group(1)) if enc_match else 0
    dec_ms = int(dec_match.group(1)) if dec_match else 0
    inference_ms = enc_ms + dec_ms

    result["total_time_s"] = round(total_time, 3)
    result["inference_time_s"] = round(inference_ms / 1000, 3)
    result["load_time_s"] = round(total_time - inference_ms / 1000, 3)
    result["transcribe_time_s"] = round(inference_ms / 1000, 3)
    result["gpu_mb"] = float(load_match.group(1)) if load_match else None

    if enc_match:
        result["encoder_ms"] = int(enc_match.group(1))
    if dec_match:
        result["decoder_ms"] = int(dec_match.group(1))
        result["prefill_ms"] = int(dec_match.group(2))
        result["step_ms"] = float(dec_match.group(3))

    result["audio_duration_s"] = round(get_audio_duration(audio_path), 3)
    result["rtf"] = round(result["transcribe_time_s"] / result["audio_duration_s"], 3)

    return result


def print_result(r: dict) -> None:
    if "error" in r:
        print(f"  ERROR: {r['error']}")
        return
    print(f"  Model:      {r.get('model', '?')}")
    print(f"  Device:     {r.get('device', '?')}")
    print(f"  Load:       {r.get('load_time_s', '?')}s")
    print(f"  Inference:  {r.get('transcribe_time_s', '?')}s")
    print(f"  RTF:        {r.get('rtf', '?')}x (lower = faster)")
    if r.get("encoder_ms"):
        print(f"  Encoder:    {r['encoder_ms']}ms")
    if r.get("decoder_ms"):
        print(f"  Decoder:    {r['decoder_ms']}ms (prefill {r.get('prefill_ms')}ms + {r.get('step_ms')}ms/step)")
    if r.get("gpu_mb"):
        print(f"  GPU mem:    {r['gpu_mb']:.0f} MB")
    print(f"  Transcript: {r.get('transcript', '(none)')}")


def main():
    audio_dur = get_audio_duration(AUDIO_PATH)
    print("=" * 64)
    print("  EchoPanel ASR Benchmark (local only, no API)")
    print("=" * 64)
    print(f"  Audio:    {AUDIO_PATH}")
    print(f"  Duration: {audio_dur:.2f}s")
    print(f"  Date:     {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 64)
    print()

    results = []

    print("── Faster-Whisper (base.en, CPU, int8) ──")
    r1 = test_faster_whisper(AUDIO_PATH, "base.en")
    print_result(r1)
    results.append(r1)
    print()

    print("── Voxtral Realtime 4B (voxtral.c, MPS, local) ──")
    r2 = test_voxtral_local(AUDIO_PATH)
    print_result(r2)
    results.append(r2)
    print()

    print("=" * 64)
    print("  Summary")
    print("=" * 64)
    print(f"  {'Provider':<20} {'RTF':<8} {'Inference':<12} {'Load':<8} {'Transcript'}")
    print(f"  {'-'*20} {'-'*8} {'-'*12} {'-'*8} {'-'*30}")
    for r in results:
        if "error" in r:
            print(f"  {r.get('provider','?'):<20} {'ERR':<8} {'-':<12} {'-':<8} {r['error'][:40]}")
        else:
            print(
                f"  {r.get('provider','?'):<20} "
                f"{r.get('rtf','?'):<8} "
                f"{str(r.get('transcribe_time_s','?'))+'s':<12} "
                f"{str(r.get('load_time_s','?'))+'s':<8} "
                f"{r.get('transcript','')[:40]}"
            )
    print()

    out_path = RESULTS_DIR / "comparison_result.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"  Results saved to: {out_path}")
    print("=" * 64)


if __name__ == "__main__":
    main()
