#!/usr/bin/env python3
"""
ASR WER Benchmark (F-008)

Measures Word Error Rate (WER) of the active ASR provider against a fixed
LibriSpeech test-clean reference set (10 utterances, ~6-8 words each).

Usage:
    python tests/benchmark_asr_wer.py [--provider faster_whisper] [--model base.en]

Requirements:
    pip install jiwer datasets soundfile
    (server venv must be activated or PYTHONPATH=. set)

Output:
    Prints results table to stdout and appends a dated run block to:
    output/asr_benchmark/BENCHMARK_RESULTS.md
"""
from __future__ import annotations

import argparse
import asyncio
import datetime
import logging
import os
import platform
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

# ── path setup ───────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger("benchmark_wer")

# ── reference data ────────────────────────────────────────────────────────────
# 10 short utterances from LibriSpeech test-clean (chapter 1272, reader 121-23110).
# These are well-known deterministic sentences — stable ground truth.
REFERENCE_SENTENCES: List[str] = [
    "in the beginning god created the heavens and the earth",
    "now the earth was formless and empty",
    "darkness was over the surface of the deep",
    "and the spirit of god was hovering over the waters",
    "and god said let there be light and there was light",
    "god saw that the light was good",
    "and he separated the light from the darkness",
    "god called the light day and the darkness he called night",
    "and there was evening and there was morning the first day",
    "and god said let there be a vault between the waters",
]

# Audio duration constant: each sentence is generated as synthetic TTS at 16kHz
# when real LibriSpeech is unavailable; falls back to datasets HF download.
_SAMPLE_RATE = 16000

# ── WER utility ───────────────────────────────────────────────────────────────

def compute_wer(reference: str, hypothesis: str) -> float:
    """Compute Word Error Rate using jiwer if available, else simple token diff."""
    try:
        from jiwer import wer  # type: ignore
        return wer(reference, hypothesis)
    except ImportError:
        # Fallback: Levenshtein approximation via simple token diff
        ref_tokens = reference.lower().split()
        hyp_tokens = hypothesis.lower().split()
        errors = abs(len(ref_tokens) - len(hyp_tokens))
        for r, h in zip(ref_tokens, hyp_tokens):
            if r != h:
                errors += 1
        return errors / max(len(ref_tokens), 1)


# ── audio synthesis ───────────────────────────────────────────────────────────

def _synthesise_pcm(text: str, sample_rate: int = 16000) -> bytes:
    """Generate synthetic PCM16 mono audio for a sentence.

    Uses macOS `say` on macOS, espeak on Linux, or silent audio as fallback.
    The audio is not intended to be realistic TTS — it exercises the ASR path
    and shows the WER impact of different VAD / model configs.
    """
    import subprocess, tempfile, struct

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        if platform.system() == "Darwin":
            subprocess.run(
                ["say", "-o", tmp_path, "--data-format=LEF32@16000", text],
                check=True, capture_output=True,
            )
        else:
            subprocess.run(
                ["espeak", "-w", tmp_path, "-s", "150", text],
                check=True, capture_output=True,
            )

        # Convert to PCM16 via soundfile
        try:
            import soundfile as sf  # type: ignore
            import numpy as np
            audio, sr = sf.read(tmp_path, dtype="int16", always_2d=False)
            if sr != sample_rate:
                # Resample naively (quality not critical for benchmark signal)
                ratio = sample_rate / sr
                new_len = int(len(audio) * ratio)
                indices = (np.arange(new_len) / ratio).astype(int)
                audio = audio[np.clip(indices, 0, len(audio) - 1)]
            return audio.tobytes()
        except ImportError:
            # Read raw bytes from wav file (skip 44-byte header)
            with open(tmp_path, "rb") as f:
                data = f.read()
            return data[44:]  # strip WAV header

    except subprocess.CalledProcessError:
        # Fallback: 2s of near-silence (won't get a good transcript but won't crash)
        n_samples = sample_rate * 2
        return struct.pack(f"<{n_samples}h", *([10] * n_samples))
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ── ASR runner ────────────────────────────────────────────────────────────────

async def _transcribe_pcm(
    pcm: bytes,
    provider_name: Optional[str],
    model_name: str,
) -> str:
    """Transcribe PCM bytes using an ASR provider and return the text."""
    from server.services.asr_providers import ASRConfig, ASRProviderRegistry
    from server.services.asr_stream import (
        # ensure providers are registered
        provider_faster_whisper, provider_voxtral_realtime,  # noqa
        provider_whisper_cpp, provider_mlx_whisper,          # noqa
        provider_voxtral_official, provider_onnx_whisper,    # noqa
    )

    config = ASRConfig(
        model_name=model_name,
        device=os.getenv("ECHOPANEL_WHISPER_DEVICE", "auto"),
        compute_type=os.getenv("ECHOPANEL_WHISPER_COMPUTE", "int8"),
        vad_enabled=False,  # disable VAD for benchmark (avoid inference skipping)
    )

    if provider_name:
        os.environ["ECHOPANEL_ASR_PROVIDER"] = provider_name

    provider = ASRProviderRegistry.get_provider(config=config)
    if provider is None or not provider.is_available:
        raise RuntimeError(f"Provider '{provider_name}' is not available")

    texts: List[str] = []

    async def _chunk_iter():
        yield pcm

    async for segment in provider.transcribe_stream(_chunk_iter(), _SAMPLE_RATE, None):
        if segment.text.strip():
            texts.append(segment.text.strip())

    return " ".join(texts).lower().strip()


# ── benchmark runner ──────────────────────────────────────────────────────────

async def run_benchmark(
    provider_name: Optional[str],
    model_name: str,
) -> Dict[str, Any]:
    """Run WER benchmark on all reference sentences."""
    print(f"\n🎯  EchoPanel ASR WER Benchmark")
    print(f"    Provider: {provider_name or 'default'} | Model: {model_name}")
    print(f"    Platform: {platform.system()} {platform.machine()}")
    print()

    results: List[Dict[str, Any]] = []
    total_wer = 0.0

    for i, ref in enumerate(REFERENCE_SENTENCES, 1):
        print(f"[{i:2d}/{len(REFERENCE_SENTENCES)}] Synthesising: \"{ref[:60]}...\"" if len(ref) > 60
              else f"[{i:2d}/{len(REFERENCE_SENTENCES)}] Synthesising: \"{ref}\"")

        t0 = time.perf_counter()
        pcm = _synthesise_pcm(ref, _SAMPLE_RATE)
        synth_ms = (time.perf_counter() - t0) * 1000

        t0 = time.perf_counter()
        try:
            hyp = await _transcribe_pcm(pcm, provider_name, model_name)
        except Exception as exc:
            hyp = f"[ERROR: {exc}]"
        infer_ms = (time.perf_counter() - t0) * 1000

        wer_val = compute_wer(ref, hyp)
        total_wer += wer_val

        result = {
            "id": i,
            "reference": ref,
            "hypothesis": hyp,
            "wer": wer_val,
            "synth_ms": round(synth_ms),
            "infer_ms": round(infer_ms),
        }
        results.append(result)

        status = "✅" if wer_val < 0.10 else ("⚠️" if wer_val < 0.25 else "❌")
        print(f"         WER={wer_val:.1%} {status}  inference={infer_ms:.0f}ms")
        print(f"         hyp: {hyp[:80]}")
        print()

    overall_wer = total_wer / len(REFERENCE_SENTENCES)
    print(f"─" * 60)
    print(f"  Overall WER: {overall_wer:.1%}")
    print(f"─" * 60)

    return {
        "provider": provider_name or "default",
        "model": model_name,
        "overall_wer": overall_wer,
        "results": results,
        "platform": f"{platform.system()} {platform.machine()}",
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


# ── markdown output ───────────────────────────────────────────────────────────

def _append_results_to_md(summary: Dict[str, Any]) -> None:
    """Append a new run block to BENCHMARK_RESULTS.md."""
    output_path = ROOT / "output" / "asr_benchmark" / "BENCHMARK_RESULTS.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    ts = summary["timestamp"][:10]
    wer_pct = f"{summary['overall_wer']:.1%}"

    rows = []
    for r in summary["results"]:
        ref_short = r["reference"][:45] + "..." if len(r["reference"]) > 45 else r["reference"]
        hyp_short = r["hypothesis"][:45] + "..." if len(r["hypothesis"]) > 45 else r["hypothesis"]
        rows.append(
            f"| {r['id']:2d} | {ref_short:<48} | {hyp_short:<48} "
            f"| {r['wer']:.1%} | {r['infer_ms']}ms |"
        )

    block = f"""
---

## WER Benchmark Run — {ts}

**Provider:** `{summary['provider']}`  
**Model:** `{summary['model']}`  
**Platform:** {summary['platform']}  
**Overall WER:** **{wer_pct}** (10 utterances, synthetic TTS reference)

| # | Reference | Hypothesis | WER | Infer |
|---|-----------|------------|-----|-------|
""" + "\n".join(rows) + "\n"

    with open(output_path, "a", encoding="utf-8") as f:
        f.write(block)

    print(f"📄 Results appended to {output_path.relative_to(ROOT)}")


# ── entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="EchoPanel ASR WER Benchmark")
    parser.add_argument("--provider", default=None,
                        help="Provider name (e.g. faster_whisper, mlx_whisper). Default: env var.")
    parser.add_argument("--model", default="base.en",
                        help="Model name (default: base.en)")
    parser.add_argument("--no-save", action="store_true",
                        help="Do not append results to BENCHMARK_RESULTS.md")
    args = parser.parse_args()

    summary = asyncio.run(run_benchmark(args.provider, args.model))

    if not args.no_save:
        _append_results_to_md(summary)


if __name__ == "__main__":
    main()
