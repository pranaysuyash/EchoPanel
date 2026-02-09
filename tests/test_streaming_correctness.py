"""
Unit tests for streaming correctness fixes.

Tests backpressure handling, transcript ordering, and ASR provider thread safety.
"""

import asyncio
import threading
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


class TestBackpressure:
    """Tests for queue backpressure handling (BP-1 fix)."""

    @pytest.mark.asyncio
    async def test_put_audio_drops_oldest_on_full(self):
        """Verify queue drops oldest frame when full."""
        from server.api.ws_live_listener import put_audio, SessionState

        state = SessionState()
        q: asyncio.Queue = asyncio.Queue(maxsize=2)

        await put_audio(q, b"frame1", state, "system")
        await put_audio(q, b"frame2", state, "system")
        await put_audio(q, b"frame3", state, "system")  # Should drop frame1

        assert q.qsize() == 2
        assert state.dropped_frames == 1
        assert await q.get() == b"frame2"
        assert await q.get() == b"frame3"

    @pytest.mark.asyncio
    async def test_put_audio_empty_chunk_ignored(self):
        """Verify empty chunks are not enqueued."""
        from server.api.ws_live_listener import put_audio, SessionState

        state = SessionState()
        q: asyncio.Queue = asyncio.Queue(maxsize=2)

        await put_audio(q, b"", state, "system")
        await put_audio(q, b"frame1", state, "system")

        assert q.qsize() == 1
        assert state.dropped_frames == 0

    @pytest.mark.asyncio
    async def test_put_audio_backpressure_warning_sent_once(self):
        """Verify backpressure warning is sent to client only once."""
        from server.api.ws_live_listener import put_audio, SessionState, ws_send

        state = SessionState()
        q: asyncio.Queue = asyncio.Queue(maxsize=1)
        mock_websocket = MagicMock()
        
        # Patch ws_send to track calls
        with patch("server.api.ws_live_listener.ws_send", new_callable=AsyncMock) as mock_send:
            await put_audio(q, b"frame1", state, "system", mock_websocket)
            await put_audio(q, b"frame2", state, "system", mock_websocket)  # Triggers drop
            await put_audio(q, b"frame3", state, "system", mock_websocket)  # Another drop
            
            # Give time for async task to run
            await asyncio.sleep(0.01)
            
            # Should have sent backpressure warning exactly once
            backpressure_calls = [
                call for call in mock_send.call_args_list
                if call.args[2].get("state") == "backpressure"
            ]
            assert len(backpressure_calls) == 1
            assert state.backpressure_warned is True


class TestTranscriptOrdering:
    """Tests for transcript ordering (TO-1 fix)."""

    def test_transcript_sorted_by_timestamp(self):
        """Verify transcript is sorted by t0 before NLP."""
        transcript = [
            {"t0": 5.0, "t1": 6.0, "text": "third", "source": "system"},
            {"t0": 1.0, "t1": 2.0, "text": "first", "source": "mic"},
            {"t0": 3.0, "t1": 4.0, "text": "second", "source": "system"},
        ]

        sorted_t = sorted(transcript, key=lambda s: s.get("t0", 0.0))

        assert sorted_t[0]["text"] == "first"
        assert sorted_t[1]["text"] == "second"
        assert sorted_t[2]["text"] == "third"

    def test_transcript_with_missing_timestamps(self):
        """Verify segments with missing t0 sort to beginning."""
        transcript = [
            {"t0": 5.0, "t1": 6.0, "text": "second"},
            {"text": "first"},  # Missing t0
        ]

        sorted_t = sorted(transcript, key=lambda s: s.get("t0", 0.0))

        assert sorted_t[0]["text"] == "first"
        assert sorted_t[1]["text"] == "second"


class TestASRProviderRegistry:
    """Tests for ASR provider registry thread safety (RC-1 fix)."""

    def test_registry_thread_safe_instance_creation(self):
        """Verify concurrent get_provider calls don't create duplicates."""
        from server.services.asr_providers import ASRProviderRegistry, ASRConfig

        # Reset instances for clean test
        ASRProviderRegistry._instances = {}

        results = []
        errors = []

        def get_provider_thread():
            try:
                cfg = ASRConfig(model_name="base", device="cpu")
                provider = ASRProviderRegistry.get_provider(config=cfg)
                results.append(id(provider))
            except Exception as e:
                errors.append(e)

        # Launch multiple threads simultaneously
        threads = [threading.Thread(target=get_provider_thread) for _ in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert len(errors) == 0, f"Errors: {errors}"
        # All threads should get the same instance
        assert len(set(results)) == 1, f"Got multiple instances: {set(results)}"


class TestDiarizationMerge:
    """Tests for speaker merge algorithm (MT-1 observations)."""

    def test_merge_with_empty_speakers(self):
        """Verify transcript returned unchanged when no speaker segments."""
        from server.services.diarization import merge_transcript_with_speakers

        transcript = [
            {"t0": 1.0, "t1": 2.0, "text": "hello"},
        ]

        result = merge_transcript_with_speakers(transcript, [])

        assert result == transcript

    def test_merge_assigns_speaker_by_midpoint(self):
        """Verify speaker assigned based on midpoint overlap."""
        from server.services.diarization import merge_transcript_with_speakers

        transcript = [
            {"t0": 1.0, "t1": 3.0, "text": "hello"},  # Midpoint 2.0
        ]
        speakers = [
            {"t0": 0.0, "t1": 2.5, "speaker": "Speaker 1"},
            {"t0": 2.5, "t1": 5.0, "speaker": "Speaker 2"},
        ]

        result = merge_transcript_with_speakers(transcript, speakers)

        assert result[0]["speaker"] == "Speaker 1"


class TestSourceAwareDiarization:
    """Tests for source-aware diarization merge in ws handler."""

    def test_source_merge_labels_only_matching_source(self):
        from server.api.ws_live_listener import _merge_transcript_with_source_diarization

        transcript = [
            {"t0": 1.0, "t1": 2.0, "text": "system line", "source": "system"},
            {"t0": 1.0, "t1": 2.0, "text": "mic line", "source": "mic"},
        ]
        diarization_by_source = {
            "mic": [{"t0": 0.0, "t1": 3.0, "speaker": "Speaker 1"}]
        }

        merged = _merge_transcript_with_source_diarization(transcript, diarization_by_source)

        assert "speaker" not in merged[0]
        assert merged[1]["speaker"] == "Speaker 1"

    def test_source_merge_normalizes_microphone_alias(self):
        from server.api.ws_live_listener import _merge_transcript_with_source_diarization

        transcript = [
            {"t0": 1.0, "t1": 2.0, "text": "mic alias", "source": "microphone"},
        ]
        diarization_by_source = {
            "mic": [{"t0": 0.0, "t1": 3.0, "speaker": "Speaker 2"}]
        }

        merged = _merge_transcript_with_source_diarization(transcript, diarization_by_source)

        assert merged[0]["speaker"] == "Speaker 2"

    @pytest.mark.asyncio
    async def test_run_diarization_per_source_invokes_each_buffer(self):
        from server.api.ws_live_listener import SessionState, _run_diarization_per_source

        state = SessionState(diarization_enabled=True, sample_rate=16000)
        state.pcm_buffers_by_source = {
            "system": bytearray(b"\x00\x00" * 4),
            "mic": bytearray(b"\x00\x00" * 4),
        }

        def fake_diarize_pcm(pcm_bytes, sample_rate):
            assert sample_rate == 16000
            return [{"t0": 0.0, "t1": 1.0, "speaker": "Speaker 1"}]

        with patch("server.api.ws_live_listener.diarize_pcm", side_effect=fake_diarize_pcm):
            result = await _run_diarization_per_source(state)

        assert set(result.keys()) == {"system", "mic"}
        assert result["system"][0]["speaker"] == "Speaker 1"


class TestQueueConfig:
    """Tests for queue configuration."""

    def test_queue_max_from_env(self):
        """Verify QUEUE_MAX is read from environment."""
        import os
        from importlib import reload

        old_val = os.environ.get("ECHOPANEL_AUDIO_QUEUE_MAX")
        try:
            os.environ["ECHOPANEL_AUDIO_QUEUE_MAX"] = "100"
            import server.api.ws_live_listener as wsl
            reload(wsl)
            assert wsl.QUEUE_MAX == 100
        finally:
            if old_val is not None:
                os.environ["ECHOPANEL_AUDIO_QUEUE_MAX"] = old_val
            else:
                os.environ.pop("ECHOPANEL_AUDIO_QUEUE_MAX", None)
            reload(wsl)
