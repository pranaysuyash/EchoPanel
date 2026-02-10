#!/usr/bin/env bash
# benchmark_asr.sh — Compare Faster-Whisper vs Voxtral Realtime on test audio
#
# Prerequisites:
#   1. Faster-Whisper: pip install faster-whisper numpy (already in pyproject.toml[asr])
#   2. Voxtral.c:     Clone & build https://github.com/antirez/voxtral.c
#                     Then run ./download_model.sh to get the 8.9GB model
#
# Usage:
#   ./scripts/benchmark_asr.sh [audio_file]
#   Default audio: test_speech.wav

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIO="${1:-$PROJECT_ROOT/test_speech.wav}"
VOXTRAL_DIR="${VOXTRAL_DIR:-$PROJECT_ROOT/../voxtral.c}"
VOXTRAL_MODEL="${VOXTRAL_MODEL:-$VOXTRAL_DIR/voxtral-model}"
RESULTS_DIR="$PROJECT_ROOT/output/asr_benchmark"

mkdir -p "$RESULTS_DIR"

echo "================================================================"
echo "  EchoPanel ASR Benchmark"
echo "================================================================"
echo "Audio:    $AUDIO"
echo "Duration: $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO" 2>/dev/null || echo 'unknown')s"
echo "Machine:  $(sysctl -n hw.model 2>/dev/null || hostname)"
echo "RAM:      $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $0/1024/1024/1024}')"
echo "Date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"
echo

# ── 1. Faster-Whisper ──────────────────────────────────────────────
echo "── Test 1: Faster-Whisper (base.en, CPU, int8) ──"

FW_SCRIPT=$(mktemp /tmp/fw_bench_XXXX.py)
cat > "$FW_SCRIPT" << 'PYEOF'
import sys, time, json

audio_path = sys.argv[1]
output_path = sys.argv[2]

try:
    from faster_whisper import WhisperModel
    import numpy as np
except ImportError:
    print("ERROR: faster-whisper not installed. Run: pip install faster-whisper numpy")
    sys.exit(1)

results = {"provider": "faster_whisper", "model": "base.en", "device": "cpu", "compute": "int8"}

# Load model
t0 = time.perf_counter()
model = WhisperModel("base.en", device="cpu", compute_type="int8")
results["load_time_s"] = round(time.perf_counter() - t0, 3)
print(f"  Model loaded in {results['load_time_s']:.3f}s")

# Transcribe
t0 = time.perf_counter()
segments, info = model.transcribe(audio_path, language="en")
segments = list(segments)
results["transcribe_time_s"] = round(time.perf_counter() - t0, 3)
results["language"] = info.language
results["language_probability"] = round(info.language_probability, 3)

# Collect output
texts = []
for seg in segments:
    texts.append(seg.text.strip())
    print(f"  [{seg.start:.1f}-{seg.end:.1f}] {seg.text.strip()}")

results["transcript"] = " ".join(texts)
results["num_segments"] = len(segments)

# Audio duration
import wave
with wave.open(audio_path, 'rb') as wf:
    audio_dur = wf.getnframes() / wf.getframerate()
results["audio_duration_s"] = round(audio_dur, 3)
results["rtf"] = round(results["transcribe_time_s"] / audio_dur, 3)  # Real-time factor

print(f"  Transcribe time: {results['transcribe_time_s']:.3f}s")
print(f"  RTF: {results['rtf']:.3f}x (lower = faster)")
print(f"  Segments: {results['num_segments']}")

with open(output_path, 'w') as f:
    json.dump(results, f, indent=2)
PYEOF

FW_OUT="$RESULTS_DIR/faster_whisper_result.json"
python3 "$FW_SCRIPT" "$AUDIO" "$FW_OUT" 2>&1 || echo "  SKIPPED: Faster-Whisper failed"
rm -f "$FW_SCRIPT"
echo

# ── 2. Faster-Whisper large-v3-turbo ──────────────────────────────
echo "── Test 2: Faster-Whisper (distil-large-v3, CPU, int8) ──"

FW2_SCRIPT=$(mktemp /tmp/fw2_bench_XXXX.py)
cat > "$FW2_SCRIPT" << 'PYEOF'
import sys, time, json

audio_path = sys.argv[1]
output_path = sys.argv[2]

try:
    from faster_whisper import WhisperModel
    import numpy as np
except ImportError:
    print("ERROR: faster-whisper not installed")
    sys.exit(1)

results = {"provider": "faster_whisper", "model": "distil-large-v3", "device": "cpu", "compute": "int8"}

t0 = time.perf_counter()
model = WhisperModel("distil-large-v3", device="cpu", compute_type="int8")
results["load_time_s"] = round(time.perf_counter() - t0, 3)
print(f"  Model loaded in {results['load_time_s']:.3f}s")

t0 = time.perf_counter()
segments, info = model.transcribe(audio_path, language="en")
segments = list(segments)
results["transcribe_time_s"] = round(time.perf_counter() - t0, 3)
results["language"] = info.language
results["language_probability"] = round(info.language_probability, 3)

texts = []
for seg in segments:
    texts.append(seg.text.strip())
    print(f"  [{seg.start:.1f}-{seg.end:.1f}] {seg.text.strip()}")

results["transcript"] = " ".join(texts)
results["num_segments"] = len(segments)

import wave
with wave.open(audio_path, 'rb') as wf:
    audio_dur = wf.getnframes() / wf.getframerate()
results["audio_duration_s"] = round(audio_dur, 3)
results["rtf"] = round(results["transcribe_time_s"] / audio_dur, 3)

print(f"  Transcribe time: {results['transcribe_time_s']:.3f}s")
print(f"  RTF: {results['rtf']:.3f}x")
print(f"  Segments: {results['num_segments']}")

with open(output_path, 'w') as f:
    json.dump(results, f, indent=2)
PYEOF

FW2_OUT="$RESULTS_DIR/faster_whisper_distil_result.json"
python3 "$FW2_SCRIPT" "$AUDIO" "$FW2_OUT" 2>&1 || echo "  SKIPPED: distil-large-v3 failed (may need download)"
rm -f "$FW2_SCRIPT"
echo

# ── 3. Voxtral Realtime (voxtral.c, MPS) ─────────────────────────
echo "── Test 3: Voxtral Realtime 4B (voxtral.c, MPS) ──"

if [ -x "$VOXTRAL_DIR/voxtral" ] && [ -d "$VOXTRAL_MODEL" ]; then
    VOX_OUT="$RESULTS_DIR/voxtral_realtime_result.json"

    t0=$(python3 -c "import time; print(time.perf_counter())")
    VOXTRAL_TEXT=$("$VOXTRAL_DIR/voxtral" -d "$VOXTRAL_MODEL" -i "$AUDIO" --silent 2>/dev/null)
    t1=$(python3 -c "import time; print(time.perf_counter())")

    VOX_TIME=$(python3 -c "print(round($t1 - $t0, 3))")
    AUDIO_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO" 2>/dev/null)
    VOX_RTF=$(python3 -c "print(round($VOX_TIME / $AUDIO_DUR, 3))")

    echo "  Transcript: $VOXTRAL_TEXT"
    echo "  Transcribe time: ${VOX_TIME}s"
    echo "  RTF: ${VOX_RTF}x"

    python3 -c "
import json
results = {
    'provider': 'voxtral_realtime',
    'model': 'Voxtral-Mini-4B-Realtime-2602',
    'device': 'mps',
    'compute': 'bf16',
    'transcript': '''$VOXTRAL_TEXT''',
    'transcribe_time_s': $VOX_TIME,
    'audio_duration_s': $AUDIO_DUR,
    'rtf': $VOX_RTF,
}
with open('$VOX_OUT', 'w') as f:
    json.dump(results, f, indent=2)
"
else
    echo "  SKIPPED: voxtral.c not found at $VOXTRAL_DIR"
    echo "  To set up:"
    echo "    cd $PROJECT_ROOT/.."
    echo "    git clone https://github.com/antirez/voxtral.c"
    echo "    cd voxtral.c"
    echo "    make mps"
    echo "    ./download_model.sh   # ~8.9GB download"
    echo "  Then re-run this script."
fi
echo

# ── 4. Voxtral Realtime (Python reference) ────────────────────────
echo "── Test 4: Voxtral Realtime 4B (Python reference impl) ──"

VOX_PY="$VOXTRAL_DIR/python_simple_implementation.py"
if [ -f "$VOX_PY" ] && [ -d "$VOXTRAL_MODEL" ]; then
    VOX_PY_OUT="$RESULTS_DIR/voxtral_python_result.txt"
    t0=$(python3 -c "import time; print(time.perf_counter())")
    python3 "$VOX_PY" "$VOXTRAL_MODEL" "$AUDIO" > "$VOX_PY_OUT" 2>&1
    t1=$(python3 -c "import time; print(time.perf_counter())")
    VOX_PY_TIME=$(python3 -c "print(round($t1 - $t0, 3))")
    echo "  Output: $(head -5 "$VOX_PY_OUT")"
    echo "  Total time: ${VOX_PY_TIME}s"
else
    echo "  SKIPPED: python_simple_implementation.py not found"
fi
echo

# ── Summary ───────────────────────────────────────────────────────
echo "================================================================"
echo "  Summary"
echo "================================================================"

SUMMARY_SCRIPT=$(mktemp /tmp/summary_XXXX.py)
cat > "$SUMMARY_SCRIPT" << 'PYEOF'
import json, os, sys

results_dir = sys.argv[1]
rows = []

for fname in sorted(os.listdir(results_dir)):
    if fname.endswith('.json'):
        with open(os.path.join(results_dir, fname)) as f:
            data = json.load(f)
        rows.append(data)

if not rows:
    print("  No results found.")
    sys.exit(0)

print(f"  {'Provider':<25} {'Model':<22} {'Device':<6} {'Load(s)':<8} {'Trans(s)':<9} {'RTF':<6}")
print(f"  {'-'*25} {'-'*22} {'-'*6} {'-'*8} {'-'*9} {'-'*6}")

for r in rows:
    provider = r.get('provider', '?')
    model = r.get('model', '?')
    device = r.get('device', '?')
    load = r.get('load_time_s', '-')
    trans = r.get('transcribe_time_s', '-')
    rtf = r.get('rtf', '-')
    print(f"  {provider:<25} {model:<22} {device:<6} {str(load):<8} {str(trans):<9} {str(rtf):<6}")

print()
print("  Transcripts:")
for r in rows:
    provider = r.get('provider', '?')
    model = r.get('model', '?')
    text = r.get('transcript', '(none)')
    print(f"  [{provider}/{model}]")
    print(f"    {text[:200]}")
    print()
PYEOF

python3 "$SUMMARY_SCRIPT" "$RESULTS_DIR"
rm -f "$SUMMARY_SCRIPT"

echo "Results saved to: $RESULTS_DIR/"
echo "================================================================"
