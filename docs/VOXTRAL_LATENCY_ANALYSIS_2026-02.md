# Voxtral Latency Analysis — February 2026

## 1. Executive Summary

EchoPanel benchmarked `voxtral.c` locally on an M3 Max (96 GB, 40-core GPU): **3.37 s inference for 4.39 s audio (0.768× RTF)**. Mistral claims "sub-200 ms latency" for Voxtral Realtime. These are **not contradictory** — they measure different things.

The "sub-200 ms" refers to **streaming transcription delay** (the gap between speech occurring and text appearing in a continuous stream), not the total wall-clock time to process a batch of audio. Our 3.37 s number is a **batch inference** measurement where the entire audio file is processed start-to-finish.

---

## 2. Source Analysis

### Mistral official sources

| Source | Claim | Context |
|---|---|---|
| [mistral.ai/news/voxtral-transcribe-2](https://mistral.ai/news/voxtral-transcribe-2) | "latency configurable down to sub-200 ms" | Streaming delay in the model's architecture, not total processing time. "At 480 ms delay, it stays within 1–2 % WER of batch model." |
| [HuggingFace model card](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602) | "delay of < 500 ms", "configurable transcription delays (240 ms to 2.4 s)" | Recommended delay: 480 ms. Explicitly states the model needs vLLM for production serving: "Due to its novel architecture, Voxtral Realtime is currently only supported in vLLM." |
| [docs.mistral.ai model page](https://docs.mistral.ai/models/voxtral-mini-transcribe-realtime-26-02) | $0.006/min API pricing | No local inference benchmarks provided. |
| Guillaume Lample (Mistral co-founder) on X | "latency configurable to sub-200 ms", "available on the Mistral API" | Refers to API serving, not local inference. |

**Evidence tag: Observed** — all claims verified by reading the linked pages on 2026-02-10.

### Community / third-party sources

| Source | Claim | Context |
|---|---|---|
| [Red Hat developers article](https://developers.redhat.com/articles/2026/02/06/run-voxtral-mini-4b-realtime-vllm-red-hat-ai) | "sub-500 ms latency" (note: 500 ms, not 200 ms) | Requires NVIDIA GPU with 16 GB+ VRAM. Uses vLLM serving with `/v1/realtime` WebSocket endpoint. Server-grade GPU inference, not consumer laptop. |
| [Reddit r/LocalLLaMA thread](https://www.reddit.com/r/LocalLLaMA/comments/1qvvcd6/) | Title says "STT in under 200 ms" | No user reports achieving this locally. One user notes "4B is still too big for most applications that'd actually need real time performance." No benchmarks posted. |

**Evidence tag: Observed** — content verified on 2026-02-10.

### antirez/voxtral.c (the implementation EchoPanel uses)

| Source | Claim | Context |
|---|---|---|
| [GitHub README](https://github.com/antirez/voxtral.c) | "MPS inference is decently fast" | Not claiming sub-200 ms. States "More testing needed" and "likely requires some more work to be production quality." |
| [SPEED.md](https://github.com/antirez/voxtral.c/blob/main/SPEED.md) | Encoder 284 ms, Prefill 252 ms, Decoder 23.5 ms/step (optimized) | Benchmarked on M3 Max **128 GB** (400 GB/s bandwidth). Achieved 73 % of theoretical bandwidth limit after 14 optimization passes. Theoretical decoder floor: 17.3 ms/step. |

**Evidence tag: Observed** — README and SPEED.md read directly.

---

## 3. What "Sub-200 ms Latency" Actually Means

The "sub-200 ms" claim describes **streaming pipeline delay**, not batch processing time.

- The model produces 1 token per 80 ms of audio.
- In streaming mode (vLLM or `voxtral.c --stdin`), the model is already loaded and warm.
- Audio flows in continuously; text comes out with a configurable delay.
- At **480 ms delay** setting: text appears 480 ms after the speech it represents (recommended; WER stays within 1–2 % of batch).
- At **200 ms delay**: text appears 200 ms after speech, but with higher WER (12.6 % vs 8.7 % average on FLEURS).
- This is a **pipeline latency metric**, NOT "time to process X seconds of audio."

**Analogy:** A video codec running at 30 fps has 33 ms frame delay even though encoding a full video takes minutes. The "delay" and "total processing time" are fundamentally different measurements.

**Evidence tag: Observed** — delay/WER tradeoff numbers from HuggingFace model card and mistral.ai blog.

---

## 4. Why Our Benchmark Shows 3.4 s

### Our results (M3 Max 96 GB, voxtral.c batch mode)

| Stage | Time |
|---|---|
| Encoder | 638 ms |
| Decoder prefill | 316 ms |
| Decoder steps (66 × 37.1 ms) | 2,412 ms |
| **Total inference** | **3,366 ms** |

**Evidence tag: Observed** — measured directly on EchoPanel hardware.

### antirez's optimized results (M3 Max 128 GB, voxtral.c batch mode)

| Stage | Time |
|---|---|
| Encoder | 284 ms |
| Decoder prefill | 252 ms |
| Decoder steps (55 × 23.5 ms) | ~1,293 ms |
| **Total inference** | **~1,829 ms** |

**Evidence tag: Observed** — from SPEED.md in the voxtral.c repository.

### Why ours is slower

**Evidence tag: Inferred** — the following are reasonable conclusions, not directly verified.

1. **Older build.** Our `voxtral.c` build may predate antirez's full optimization passes. He went from 43.2 → 23.5 ms/step across 14 iterations documented in SPEED.md. Our 37.1 ms/step sits between those extremes.
2. **Memory bandwidth.** The 128 GB M3 Max has 400 GB/s. Some 96 GB M3 Max configurations have 300 GB/s, which would explain the ~1.6× slower decoder step (37.1 / 23.5 ≈ 1.58×, roughly consistent with 400 / 300 ≈ 1.33× plus other overhead). However, the 40-core GPU 96 GB M3 Max *should* have 400 GB/s — **this needs verification** (see §8).
3. **Thermal throttling or background processes** during the benchmark.

### Even optimized batch mode is not "sub-200 ms"

- Optimized batch: 284 + 252 + 1,293 = **1,829 ms** for 4.39 s audio.
- This is 0.42× RTF — very good, but still 1.8 seconds total latency per chunk.
- The "sub-200 ms" is only achievable in **streaming mode** where the model processes audio incrementally as it arrives.

---

## 5. The EchoPanel Provider Architecture Problem

The current `provider_voxtral_realtime.py` has a fundamental flaw:

| Step | Time |
|---|---|
| Spawn new `voxtral.c` subprocess | ~11 s (model mmap + GPU cache warmup) |
| Inference | ~3.4 s |
| **Total per 4 s audio chunk** | **~14.4 s** |

This is **3.6× slower than real-time** — completely unusable for live transcription.

**Evidence tag: Observed** — cold-start overhead measured in EchoPanel integration testing.

### voxtral.c supports streaming mode that would fix this

| Feature | Flag / API | Effect |
|---|---|---|
| Streaming stdin | `--stdin` | Pipe raw PCM audio continuously; model stays resident |
| Processing interval | `-I <seconds>` | Controls latency/efficiency tradeoff |
| Direct mic capture | `--from-mic` | Microphone input with silence detection; bypasses EchoPanel's PCM pipeline |
| C API | `vox_stream_feed()` + `vox_stream_get()` | Incremental processing for embedded use |

With the model warm and streaming, the decoder step (23.5 ms) is well under the 80 ms per-token budget, so the model **keeps up with real-time audio**.

**Evidence tag: Observed** — flags and API documented in voxtral.c README and source.

---

## 6. Corrected Comparison Table

| Metric | Mistral claim | Our measurement | Apples-to-apples? |
|---|---|---|---|
| "Sub-200 ms latency" | Streaming delay (speech → text gap) in vLLM/API | N/A (we measured batch) | **No** — different metric |
| Batch inference, 4.39 s audio | Not claimed | 3.37 s (our build), ~1.83 s (optimized) | N/A |
| RTF (batch) | Not claimed | 0.768× (our build), ~0.42× (optimized) | N/A |
| Keeps up with real-time? | Yes (via streaming) | Yes (23.5 ms/step < 80 ms/token budget) | **Yes** — confirmed by antirez |
| Memory | "minimal hardware" / "on-device" | 16 GB GPU + 25 GB total | Misleading for 8 GB machines |

---

## 7. Corrected Recommendations

| Use case | Provider | Why |
|---|---|---|
| Live streaming (default) | faster-whisper `base.en` | 0.127× RTF, ~200 MB RAM, works offline, proven |
| Live streaming (Voxtral) | voxtral.c with `--stdin` streaming | Must keep model resident; viable on ≥ 16 GB GPU machines; **needs provider rewrite** |
| Post-session re-transcription | voxtral.c batch mode | Higher accuracy on long/noisy audio; 11 s cold start acceptable for batch |
| Offline fallback | faster-whisper `base.en` | No network, no GPU requirements |

### Provider rewrite needed

`provider_voxtral_realtime.py` must be rewritten to use voxtral.c as a **long-running process** with `--stdin`, piping PCM audio in and reading tokens from stdout. This eliminates the 11 s cold start per chunk and enables true streaming transcription.

---

## 8. Open Questions

- [ ] Verify M3 Max 96 GB / 40-core GPU memory bandwidth (400 GB/s or 300 GB/s?)
- [ ] Rebuild voxtral.c from latest `main` to get all 14 optimization passes
- [ ] Benchmark streaming mode (`--stdin -I 0.5`) for true streaming latency measurement
- [ ] Test `--from-mic` mode for direct microphone integration (bypasses EchoPanel's PCM pipeline)
- [ ] Test on M1/M2 MacBook Air (8 GB) to confirm it is not viable there
- [ ] Test with longer audio (30–60 min) to compare WER between faster-whisper and voxtral

**Evidence tag: Unknown** — all items above require future investigation.

---

## 9. Sources Consulted

All sources accessed 2026-02-10.

| # | URL |
|---|---|
| 1 | https://mistral.ai/news/voxtral-transcribe-2 |
| 2 | https://docs.mistral.ai/models/voxtral-mini-transcribe-realtime-26-02 |
| 3 | https://docs.mistral.ai/getting-started/models/compare?models=voxtral-mini-transcribe-realtime-26-02,voxtral-mini-transcribe-26-02,voxtral-mini-transcribe-25-07 |
| 4 | https://x.com/GuillaumeLample/status/2019097517569302840 |
| 5 | https://www.reddit.com/r/LocalLLaMA/comments/1qvvcd6/ |
| 6 | https://developers.redhat.com/articles/2026/02/06/run-voxtral-mini-4b-realtime-vllm-red-hat-ai |
| 7 | https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602 |
| 8 | https://github.com/antirez/voxtral.c (README + SPEED.md) |
