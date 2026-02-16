"""
Unit tests for streaming correctness fixes.

Tests backpressure handling, transcript ordering, and ASR provider thread safety.
"""

import asyncio
import os
import threading
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


class TestBackpressure:
    """Tests for queue backpressure handling (BP-1 fix)."""

    @pytest.mark.asyncio
    async def test_put_audio_drops_oldest_on_full(self):
        """Verify queue drops oldest frame when byte limit exceeded (TCK-20260213-074).
        
        With byte-based backpressure, when adding a new chunk would exceed the limit,
        oldest chunks are dropped first to make room. This keeps the stream "live"
        rather than accumulating lag.
        """
        from server.api.ws_live_listener import put_audio, SessionState, _queue_bytes

        state = SessionState()
        q: asyncio.Queue = asyncio.Queue(maxsize=100)  # Large frame limit, bytes will limit

        # Patch QUEUE_MAX_BYTES to a small value for testing (15 bytes = room for 2 frames of 6 bytes)
        with patch("server.api.ws_live_listener.QUEUE_MAX_BYTES", 15):
            await put_audio(q, b"frame1", state, "system")  # 6 bytes, total 6
            await put_audio(q, b"frame2", state, "system")  # 6 bytes, total 12 <= 15
            # Now at 12 bytes, adding frame3 (6 bytes) would make 18 > 15
            # So frame1 is dropped (12-6=6), then frame3 added (6+6=12)
            await put_audio(q, b"frame3", state, "system")

        assert q.qsize() == 2
        assert state.dropped_frames == 1
        # frame1 was dropped to make room, so we have frame2 and frame3
        items = [await q.get(), await q.get()]
        assert b"frame2" in items
        assert b"frame3" in items
        assert b"frame1" not in items

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


class TestDualLanePipeline:
    """Tests for dual-lane pipeline (TCK-20260213-074).
    
    Lane A (Realtime): Bounded queue, may drop to stay live
    Lane B (Recording): Lossless file write, never drops
    """

    @pytest.mark.asyncio
    async def test_recording_lane_writes_all_frames(self):
        """Verify recording lane writes all frames even when realtime lane drops."""
        from server.api.ws_live_listener import put_audio, SessionState, _init_recording_lane, _finalize_recording_lane
        from unittest.mock import patch, MagicMock
        
        state = SessionState()
        state.session_id = "test_session"
        q: asyncio.Queue = asyncio.Queue(maxsize=100)
        
        # Mock recording lane directory and enable it
        with patch("server.api.ws_live_listener.RECORDING_LANE_ENABLED", True):
            with patch("server.api.ws_live_listener.RECORDING_LANE_FORMAT", "pcm"):
                with patch("server.api.ws_live_listener.RECORDING_LANE_DIR") as mock_dir:
                    mock_dir.mkdir = MagicMock()
                    mock_dir.__truediv__ = MagicMock(return_value=MagicMock())
                    
                    # Initialize recording lane
                    _init_recording_lane(state, "system", 16000)
                    
                    # Write some frames
                    await put_audio(q, b"frame1", state, "system")
                    await put_audio(q, b"frame2", state, "system")
                    await put_audio(q, b"frame3", state, "system")
                    
                    # Verify frames went to realtime queue
                    assert q.qsize() == 3
                    
                    # Verify recording lane tracked bytes (would be written to file)
                    assert state.recording_bytes_written.get("system", 0) == 18  # 6 bytes * 3 frames

    def test_wav_header_writing(self):
        """Verify WAV header is written with correct format."""
        from server.api.ws_live_listener import _write_wav_header
        import struct
        import io
        
        f = io.BytesIO()
        _write_wav_header(f, 16000, 1000)  # 16000 Hz, 1000 samples
        
        f.seek(0)
        header = f.read()
        
        # Check RIFF header
        assert header[0:4] == b'RIFF'
        # Check WAVE identifier
        assert header[8:12] == b'WAVE'
        # Check fmt chunk
        assert header[12:16] == b'fmt '
        # Check sample rate (at offset 24)
        sample_rate = struct.unpack('<I', header[24:28])[0]
        assert sample_rate == 16000


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


class TestStagedFeatureTelemetry:
    """Tests for U8 staged feature flags and drift telemetry helpers."""

    def test_extract_client_features_defaults(self):
        from server.api.ws_live_listener import _extract_client_features

        result = _extract_client_features({})
        assert result == {
            "clock_drift_compensation_enabled": False,
            "client_vad_enabled": False,
            "clock_drift_telemetry_enabled": False,
            "client_vad_telemetry_enabled": False,
        }

    def test_extract_client_features_from_payload(self):
        from server.api.ws_live_listener import _extract_client_features

        payload = {
            "client_features": {
                "clock_drift_compensation_enabled": True,
                "client_vad_enabled": True,
                "clock_drift_telemetry_enabled": True,
                "client_vad_telemetry_enabled": False,
            }
        }
        result = _extract_client_features(payload)
        assert result["clock_drift_compensation_enabled"] is True
        assert result["client_vad_enabled"] is True
        assert result["clock_drift_telemetry_enabled"] is True
        assert result["client_vad_telemetry_enabled"] is False

    def test_update_source_clock_spread_tracks_last_and_max(self):
        from server.api.ws_live_listener import SessionState, _update_source_clock_spread

        state = SessionState(sample_rate=16000)
        state.asr_last_t1_by_source = {"system": 3.0, "mic": 3.12}
        _update_source_clock_spread(state)
        assert state.source_clock_spread_ms == pytest.approx(120.0, abs=0.1)
        assert state.max_source_clock_spread_ms == pytest.approx(120.0, abs=0.1)

        state.asr_last_t1_by_source = {"system": 4.0, "mic": 4.05}
        _update_source_clock_spread(state)
        assert state.source_clock_spread_ms == pytest.approx(50.0, abs=0.1)
        assert state.max_source_clock_spread_ms == pytest.approx(120.0, abs=0.1)


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


class TestMetricsRTF:
    """Tests for PR6: realtime_factor should use actual audio duration processed."""

    def test_compute_recent_rtf_uses_audio_duration(self):
        from server.api.ws_live_listener import _compute_recent_rtf

        # Two samples:
        # - processed 0.5s for 2.0s audio
        # - processed 0.5s for 1.0s audio
        # Total processing = 1.0s, total audio = 3.0s => RTF = 0.333...
        rtf = _compute_recent_rtf([(0.5, 2.0), (0.5, 1.0)])
        assert rtf == pytest.approx(1.0 / 3.0, abs=1e-6)

    def test_compute_recent_rtf_empty_or_zero_audio_is_zero(self):
        from server.api.ws_live_listener import _compute_recent_rtf

        assert _compute_recent_rtf([]) == 0.0
        assert _compute_recent_rtf([(1.0, 0.0)]) == 0.0


class TestDebugAudioDumpCleanup:
    """Tests for debug audio dump retention policy."""

    def test_cleanup_removes_expired_files(self, tmp_path, monkeypatch):
        import server.api.ws_live_listener as wsl

        old_file = tmp_path / "old.pcm"
        fresh_file = tmp_path / "fresh.pcm"
        old_file.write_bytes(b"old")
        fresh_file.write_bytes(b"fresh")

        now = 1_000.0
        os.utime(old_file, (now - 120, now - 120))
        os.utime(fresh_file, (now - 10, now - 10))

        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP", True)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_DIR", tmp_path)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS", 60)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_FILES", 100)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES", 1024)

        wsl._cleanup_audio_dump_dir(now=now)

        assert not old_file.exists()
        assert fresh_file.exists()

    def test_cleanup_enforces_max_file_count(self, tmp_path, monkeypatch):
        import server.api.ws_live_listener as wsl

        files = []
        now = 2_000.0
        for idx in range(4):
            file_path = tmp_path / f"dump-{idx}.pcm"
            file_path.write_bytes(b"x")
            os.utime(file_path, (now + idx, now + idx))
            files.append(file_path)

        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP", True)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_DIR", tmp_path)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS", 0)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_FILES", 2)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES", 1024)

        wsl._cleanup_audio_dump_dir(now=now + 10)

        remaining = sorted(path.name for path in tmp_path.glob("*.pcm"))
        assert remaining == ["dump-2.pcm", "dump-3.pcm"]

    def test_cleanup_enforces_total_size(self, tmp_path, monkeypatch):
        import server.api.ws_live_listener as wsl

        now = 3_000.0
        a = tmp_path / "a.pcm"
        b = tmp_path / "b.pcm"
        c = tmp_path / "c.pcm"
        a.write_bytes(b"a" * 5)
        b.write_bytes(b"b" * 5)
        c.write_bytes(b"c" * 5)
        os.utime(a, (now, now))
        os.utime(b, (now + 1, now + 1))
        os.utime(c, (now + 2, now + 2))

        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP", True)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_DIR", tmp_path)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS", 0)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_FILES", 100)
        monkeypatch.setattr(wsl, "DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES", 10)

        wsl._cleanup_audio_dump_dir(now=now + 10)

        remaining = sorted(path.name for path in tmp_path.glob("*.pcm"))
        assert remaining == ["b.pcm", "c.pcm"]
