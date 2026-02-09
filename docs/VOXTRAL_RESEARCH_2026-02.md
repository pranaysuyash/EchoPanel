# Voxtral Transcribe 2 — Research & Integration Notes

**Date**: February 2026  
**Scope**: Evaluating Mistral Voxtral model family as ASR replacement for EchoPanel  
**Sources**: [Voxtral announcement](https://mistral.ai/news/voxtral), [Voxtral Transcribe 2 announcement](https://mistral.ai/news/voxtral-transcribe-2), [Mistral Audio Docs](https://docs.mistral.ai/capabilities/audio/)

---

## 1. Background

EchoPanel currently uses **Faster-Whisper** (local, `base.en` default) for live transcription and **pyannote.audio** for batch diarization at session end. The ASR provider abstraction (`server/services/asr_providers.py`) already supports swappable backends via `ASRProviderRegistry`.

Mistral released the **Voxtral** model family in July 2025 and **Voxtral Transcribe 2** in early 2026. These are speech understanding models purpose-built for transcription, with the realtime variant targeting live applications.

---

## 2. Model Family Overview

### Voxtral Transcribe 2 (latest — Feb 2026)

| Model | Params | Use Case | License | Pricing | Diarization | Realtime |
|-------|--------|----------|---------|---------|-------------|----------|
| **Voxtral Realtime** | 4B | Live transcription | Apache 2.0 (open weights) | $0.006/min (API) | No | Yes, sub-200ms configurable |
| **Voxtral Mini Transcribe V2** | — | Batch transcription | API-only (proprietary) | $0.003/min | Yes (native) | No |

### Voxtral (original — July 2025)

| Model | Params | Use Case | License | Pricing |
|-------|--------|----------|---------|---------|
| Voxtral Small | 24B | Chat + audio Q&A/summarization | Apache 2.0 | API |
| Voxtral Mini | 3B | Chat + audio understanding | Apache 2.0 | API |
| Voxtral Mini Transcribe (v1) | — | Transcription-only | API | $0.001/min |
| Voxtral Mini Transcribe Realtime (v1) | — | Live transcription (v1) | API | — |

---

## 3. Voxtral Realtime — Key Details

- **Architecture**: Novel streaming architecture (not chunked offline model). Transcribes audio as it arrives.
- **Latency**: Configurable down to sub-200ms. At 480ms delay, stays within 1–2% WER of batch model. At 2.4s delay, matches batch quality exactly.
- **Languages**: 13 — English, Chinese, Hindi, Spanish, Arabic, French, Portuguese, Russian, German, Japanese, Korean, Italian, Dutch.
- **Input format**: PCM 16-bit mono (`pcm_s16le`), 16kHz sample rate — same as EchoPanel's current format.
- **Protocol**: WebSocket streaming via `client.audio.realtime.transcribe_stream()`.
- **SDK**: `pip install mistralai[realtime]` (Python), also available in TypeScript.
- **Open weights**: Available on [HuggingFace](https://huggingface.co/mistralai) under Apache 2.0. 4B parameter footprint is feasible for local inference on Apple Silicon.

### API Usage (Python)

```python
from mistralai import Mistral
from mistralai.models import AudioFormat

client = Mistral(api_key="...")
audio_format = AudioFormat(encoding="pcm_s16le", sample_rate=16000)

async for event in client.audio.realtime.transcribe_stream(
    audio_stream=pcm_iterator,
    model="voxtral-mini-transcribe-realtime-2602",
    audio_format=audio_format,
):
    # event types: RealtimeTranscriptionSessionCreated,
    #              TranscriptionStreamTextDelta,
    #              TranscriptionStreamDone,
    #              RealtimeTranscriptionError
    pass
```

---

## 4. Voxtral Mini Transcribe V2 — Key Details

- **Diarization**: Native speaker diarization with speaker labels and precise start/end times. No pyannote needed.
- **Context biasing**: Up to 100 words/phrases to guide spelling of names, technical terms.
- **Word-level timestamps**: Precise per-word start/end times.
- **Max audio length**: Up to 3 hours per request.
- **Noise robustness**: Designed for challenging acoustic environments (factory floors, call centers, field recordings).
- **Benchmark**: ~4% WER on FLEURS. Outperforms GPT-4o mini Transcribe, Gemini 2.5 Flash, Assembly Universal, Deepgram Nova. Matches ElevenLabs Scribe v2 at 1/5 the cost.

### API Usage (Python)

```python
from mistralai import Mistral

client = Mistral(api_key="...")

# Batch transcription with diarization
response = client.audio.transcriptions.complete(
    model="voxtral-mini-latest",
    file={"content": audio_file, "file_name": "meeting.mp3"},
    # Optional:
    # diarize=True,
    # timestamp_granularities=["word"],
    # context_bias="EchoPanel,ScreenCaptureKit,pyannote",
    # language="en",
)
```

---

## 5. Open-Source / Licensing Status

| Model | Open Weights | Self-Hostable | License |
|-------|-------------|---------------|---------|
| Voxtral Realtime (4B) | Yes | Yes (HuggingFace) | Apache 2.0 |
| Voxtral Mini Transcribe V2 | **No** | **No** (API-only) | Proprietary |
| Voxtral Small (24B, chat) | Yes | Yes | Apache 2.0 |
| Voxtral Mini (3B, chat) | Yes | Yes | Apache 2.0 |

**Key implication**: Diarization via V2 requires the API. A fully offline stack with diarization still needs pyannote.

---

## 6. Integration Strategy for EchoPanel

### Recommended: Try Voxtral Realtime Locally, Keep pyannote, V2 API Optional

**Primary (default)**: Faster-Whisper (local) — current setup, works offline.  
**Try out**: Voxtral Realtime (local, open-source) — self-host the 4B model, no API key needed.  
**Keep**: pyannote for diarization — already works, no paid replacement needed.  
**Optional/future**: Voxtral Mini Transcribe V2 API — only if paid plan is justified later.

| Component | Current | Try Out (open-source) | Future (paid, optional) |
|-----------|---------|----------------------|------------------------|
| **Live transcription** | Faster-Whisper | Voxtral Realtime (local, 4B) | Voxtral Realtime API ($0.006/min) |
| **Diarization** | pyannote | pyannote (keep) | Voxtral V2 API ($0.003/min) |

### Recommended Path

1. **Now**: Download Voxtral Realtime (4B) from HuggingFace. Build `provider_voxtral_realtime.py` for local inference. Test against Faster-Whisper on real meeting audio.
2. **Keep**: pyannote stays for diarization. No changes needed.
3. **Config**: `ECHOPANEL_ASR_PROVIDER=faster_whisper` (default) or `voxtral_realtime` (local open-source).
4. **Later (optional)**: If paid API is justified, add Voxtral V2 for batch diarization as an alternative to pyannote.

### Benefits Over Current Stack

- **Better accuracy**: Voxtral Realtime outperforms Whisper large-v3 on all benchmarks.
- **Lower resource usage**: Offloading to API frees local CPU/GPU (Faster-Whisper + pyannote currently consume significant memory on 8GB machines).
- **Native diarization**: V2 diarization is integrated — no separate pyannote pipeline, no HuggingFace token, no torch dependency.
- **13 languages**: vs current English-focused setup.
- **Cost**: $0.006/min realtime + $0.003/min post-session = ~$0.54 for a 1-hour meeting.

### Implementation Plan

1. **New file**: `server/services/provider_voxtral_realtime.py`
   - Implements `ASRProvider` interface
   - Loads Voxtral Realtime (4B) from HuggingFace for local inference
   - Streams PCM audio → text segments, same interface as Faster-Whisper provider
   - No API key needed (open-source model)

2. **Update**: `server/services/asr_stream.py`
   - Import and register new provider
   - Select via `ECHOPANEL_ASR_PROVIDER=voxtral_realtime`

3. **Update**: `server/requirements.txt`
   - Add HuggingFace model dependencies (transformers, etc.) as optional

4. **No changes needed**:
   - Diarization (`diarization.py`) — pyannote stays as-is
   - WebSocket protocol (`ws_live_listener.py`) — same event format
   - macOS app audio capture — same PCM16/16kHz format
   - Frontend transcript rendering — same data shape

5. **Future (optional, paid API)**:
   - `server/services/provider_voxtral_batch.py` — V2 API with native diarization
   - Requires `ECHOPANEL_MISTRAL_API_KEY` env var
   - Only build if paid plan is justified

---

## 7. Mistral API Plans & Pricing

### API Tiers

| Tier | Cost | Notes |
|------|------|-------|
| **Experiment** | Free | Rate-limited, for testing/prototyping |
| **Scale** | Pay-as-you-go | Production use, no rate limits |

Sign up at [console.mistral.ai](https://console.mistral.ai). Billing managed at [admin.mistral.ai](https://admin.mistral.ai).

### Voxtral Model Pricing (per minute of audio)

| Model | $/min | Type | Open Weights |
|-------|-------|------|-------------|
| Voxtral Mini (chat+audio) | $0.001 | Open | Yes |
| Voxtral Mini Transcribe V2 | $0.003 | Premier | No |
| Voxtral Small (chat+audio) | $0.004 | Open | Yes |
| Voxtral Realtime | $0.006 | Open | Yes |

### Cost Estimates for EchoPanel Usage

| Scenario | Monthly Audio | Realtime Cost | V2 Diarization | Total |
|----------|--------------|---------------|----------------|-------|
| Light (5 meetings/week, 30min) | 10 hours | $3.60 | $1.80 | **$5.40** |
| Medium (10 meetings/week, 45min) | 30 hours | $10.80 | $5.40 | **$16.20** |
| Heavy (20 meetings/week, 1hr) | 80 hours | $28.80 | $14.40 | **$43.20** |

The free Experiment tier is sufficient for initial testing and prototyping before committing to paid usage.

---

## 8. Comparison: Voxtral vs Current Stack

| Feature | Current (Faster-Whisper + pyannote) | Voxtral Transcribe 2 |
|---------|-------------------------------------|----------------------|
| Live WER (English) | ~5–8% (base.en) | ~3–4% (Realtime) |
| Diarization | Batch, pyannote, requires HF token + torch | Native in V2 batch API |
| Languages | English-focused (base.en) | 13 languages |
| Latency | ~2–4s chunks | Sub-200ms configurable |
| Memory footprint | ~500MB (Whisper) + ~2GB (pyannote+torch) | 0 (API) or ~4GB (local Realtime) |
| Offline capability | Full | Realtime only (open weights); V2 requires API |
| Cost | Free (local compute) | ~$0.54/hour (API) |
| Setup complexity | pip install faster-whisper; HF token for diarization | pip install mistralai[realtime]; API key |

---

## 9. Risks & Considerations

- **API dependency**: Full Voxtral path requires internet + API key. EchoPanel's "works offline" promise requires keeping Faster-Whisper as fallback.
- **Privacy**: Audio leaves the machine when using API. Must be clearly communicated in UI. Consistent with existing LLM strategy (Decision v0.3: "Transcript text can optionally be sent to your own LLM provider").
- **Cost at scale**: $0.54/hour is cheap per meeting but adds up for power users. Free local fallback mitigates this.
- **V2 diarization quality**: Not yet tested on EchoPanel's typical audio (system audio + mic, overlapping speech). Mistral notes "with overlapping speech, the model typically transcribes one speaker."
- **Voxtral Realtime local inference**: 4B model on Apple Silicon needs validation — inference speed, memory, thermal throttling on MacBook Air.

---

## 10. Next Steps

- [ ] Obtain Mistral API key and test Voxtral Realtime with EchoPanel's PCM stream
- [ ] Benchmark Voxtral Realtime vs Faster-Whisper on sample meeting audio
- [ ] Test V2 batch diarization on multi-speaker meeting recordings
- [ ] Build `provider_voxtral_realtime.py` implementing `ASRProvider`
- [ ] Build `provider_voxtral_batch.py` for post-session diarization
- [ ] Evaluate local Voxtral Realtime (4B) on M1/M2 Apple Silicon
- [ ] Update Settings UI to support Mistral API key entry
