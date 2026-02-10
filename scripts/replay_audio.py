#!/usr/bin/env python3
"""
EchoPanel Audio Replay Tool

Replays recorded PCM audio through the ASR pipeline for debugging and testing.

Usage:
    python replay_audio.py --session-bundle ./session.bundle --output ./results/
    python replay_audio.py --audio-file ./audio.pcm --config ./config.json

The tool reads audio from a session bundle or standalone file, processes it through
the same ASR pipeline used in production, and outputs the transcript for comparison.
"""

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path
from typing import AsyncIterator, Dict, List, Optional

# Add server to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from server.services.asr_stream import stream_asr
from server.services.asr_providers import AudioSource


async def read_pcm_file(file_path: Path, chunk_size: int = 32000) -> AsyncIterator[bytes]:
    """
    Read PCM file in chunks simulating real-time streaming.
    
    Default chunk_size = 32000 bytes = 2 seconds of 16kHz 16-bit mono audio
    """
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            yield chunk
            # Simulate real-time delay
            await asyncio.sleep(0.1)  # 100ms between chunks


async def replay_session(
    audio_file: Path,
    source: str = "system",
    sample_rate: int = 16000,
    output_dir: Optional[Path] = None,
) -> Dict:
    """
    Replay audio through ASR pipeline.
    
    Returns:
        Dict with transcript, metrics, and comparison data
    """
    print(f"Replaying audio: {audio_file}")
    print(f"Source: {source}, Sample rate: {sample_rate}")
    
    transcript: List[Dict] = []
    start_time = time.time()
    chunk_count = 0
    
    try:
        async for event in stream_asr(
            read_pcm_file(audio_file),
            sample_rate=sample_rate,
            source=source,
        ):
            chunk_count += 1
            
            if event.get("type") in ("asr_partial", "asr_final"):
                transcript.append({
                    "type": event.get("type"),
                    "text": event.get("text"),
                    "t0": event.get("t0"),
                    "t1": event.get("t1"),
                    "confidence": event.get("confidence"),
                    "is_final": event.get("type") == "asr_final",
                })
                
                # Print progress
                if event.get("type") == "asr_final":
                    print(f"  [{event.get('t0', 0):.1f}s] {event.get('text', '')}")
    
    except Exception as e:
        print(f"Error during replay: {e}")
        raise
    
    elapsed = time.time() - start_time
    
    results = {
        "transcript": transcript,
        "metadata": {
            "audio_file": str(audio_file),
            "source": source,
            "sample_rate": sample_rate,
            "elapsed_time_seconds": elapsed,
            "chunks_processed": chunk_count,
            "total_segments": len(transcript),
        },
    }
    
    # Save results if output directory specified
    if output_dir:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        
        transcript_file = output_dir / "transcript.json"
        with open(transcript_file, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults saved to: {transcript_file}")
    
    return results


def load_session_bundle(bundle_path: Path) -> Dict:
    """Load and parse a session bundle."""
    receipt_file = bundle_path / "receipt.json"
    
    if not receipt_file.exists():
        raise FileNotFoundError(f"Not a valid session bundle: {bundle_path}")
    
    with open(receipt_file) as f:
        receipt = json.load(f)
    
    # Load transcript for comparison
    final_transcript_file = bundle_path / "transcript_final.json"
    original_transcript = None
    if final_transcript_file.exists():
        with open(final_transcript_file) as f:
            original_transcript = json.load(f)
    
    return {
        "receipt": receipt,
        "original_transcript": original_transcript,
        "bundle_path": bundle_path,
    }


def compare_transcripts(replayed: List[Dict], original: List[Dict]) -> Dict:
    """Compare replayed transcript with original."""
    replayed_text = [seg["text"] for seg in replayed if seg.get("is_final")]
    original_text = [seg.get("text", "") for seg in original]
    
    # Simple text comparison
    matches = sum(1 for r, o in zip(replayed_text, original_text) if r == o)
    total = max(len(replayed_text), len(original_text))
    
    return {
        "replayed_segments": len(replayed_text),
        "original_segments": len(original_text),
        "exact_matches": matches,
        "match_ratio": matches / total if total > 0 else 0,
        "differences": [
            {"index": i, "replayed": r, "original": o}
            for i, (r, o) in enumerate(zip(replayed_text, original_text))
            if r != o
        ],
    }


async def main():
    parser = argparse.ArgumentParser(
        description="Replay EchoPanel audio through ASR pipeline"
    )
    parser.add_argument(
        "--session-bundle",
        type=Path,
        help="Path to session bundle directory",
    )
    parser.add_argument(
        "--audio-file",
        type=Path,
        help="Path to standalone PCM audio file",
    )
    parser.add_argument(
        "--config",
        type=Path,
        help="Path to config JSON file",
    )
    parser.add_argument(
        "--source",
        choices=["system", "mic"],
        default="system",
        help="Audio source tag",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("./replay_results"),
        help="Output directory for results",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="Compare replayed transcript with original",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Exit with error if transcripts don't match (for CI)",
    )
    
    args = parser.parse_args()
    
    if not args.session_bundle and not args.audio_file:
        parser.error("Must specify either --session-bundle or --audio-file")
    
    original_transcript = None
    
    if args.session_bundle:
        bundle = load_session_bundle(args.session_bundle)
        receipt = bundle["receipt"]
        original_transcript = bundle.get("original_transcript")
        
        print(f"Session: {receipt.get('session_id')}")
        print(f"Provider: {receipt.get('server_info', {}).get('provider')}")
        print(f"Model: {receipt.get('server_info', {}).get('model_id')}")
        
        # Find audio file in bundle
        audio_manifest = args.session_bundle / "audio_manifest.json"
        if audio_manifest.exists():
            with open(audio_manifest) as f:
                manifest = json.load(f)
            print(f"Audio included: {manifest.get('included', False)}")
            if not manifest.get("included", False):
                print("Warning: Audio not included in bundle, cannot replay")
                return 1
        
        # Look for audio files
        pcm_files = list(args.session_bundle.glob("*.pcm"))
        if pcm_files:
            args.audio_file = pcm_files[0]
        else:
            # Check audio_dump directory
            dump_files = list(args.session_bundle.glob("audio_dump/*.pcm"))
            if dump_files:
                args.audio_file = dump_files[0]
            else:
                print("Error: No audio files found in bundle")
                return 1
    
    # Replay the audio
    results = await replay_session(
        audio_file=args.audio_file,
        source=args.source,
        output_dir=args.output,
    )
    
    # Compare if requested and original available
    if args.compare and original_transcript:
        print("\n--- Comparison ---")
        comparison = compare_transcripts(
            results["transcript"],
            original_transcript
        )
        print(f"Replayed segments: {comparison['replayed_segments']}")
        print(f"Original segments: {comparison['original_segments']}")
        print(f"Exact matches: {comparison['exact_matches']}")
        print(f"Match ratio: {comparison['match_ratio']:.2%}")
        
        if comparison["differences"]:
            print(f"\nDifferences found: {len(comparison['differences'])}")
            for diff in comparison["differences"][:5]:  # Show first 5
                print(f"  [{diff['index']}] Replay: {diff['replayed']}")
                print(f"  [{diff['index']}] Origin: {diff['original']}")
        
        # Save comparison
        comparison_file = args.output / "comparison.json"
        with open(comparison_file, "w") as f:
            json.dump(comparison, f, indent=2)
        
        # Exit with error if verification requested and mismatch
        if args.verify and comparison["match_ratio"] < 0.95:
            print("\nVerification FAILED: Transcript mismatch")
            return 1
    
    print("\nReplay completed successfully")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
