from types import SimpleNamespace

from server import main


def test_prefer_whisper_cpp_for_apple_silicon(monkeypatch):
    monkeypatch.delenv("ECHOPANEL_PREFER_WHISPER_CPP", raising=False)

    class FakeDetector:
        @staticmethod
        def _whisper_cpp_available() -> bool:
            return True

    profile = SimpleNamespace(has_mps=True, ram_gb=24.0)
    recommendation = SimpleNamespace(
        provider="voxtral_realtime",
        model="Voxtral-Mini-4B-Realtime",
        chunk_seconds=2,
        compute_type="bf16",
        device="mps",
        vad_enabled=True,
        reason="High RAM with GPU",
    )

    updated = main._prefer_whisper_cpp_for_apple_silicon(FakeDetector(), profile, recommendation)
    assert updated.provider == "whisper_cpp"
    assert updated.model == "medium.en"
    assert updated.compute_type == "q5_0"


def test_skip_preference_when_flag_disabled(monkeypatch):
    monkeypatch.setenv("ECHOPANEL_PREFER_WHISPER_CPP", "0")

    class FakeDetector:
        @staticmethod
        def _whisper_cpp_available() -> bool:
            return True

    profile = SimpleNamespace(has_mps=True, ram_gb=24.0)
    recommendation = SimpleNamespace(
        provider="voxtral_realtime",
        model="Voxtral-Mini-4B-Realtime",
        chunk_seconds=2,
        compute_type="bf16",
        device="mps",
        vad_enabled=True,
        reason="High RAM with GPU",
    )

    updated = main._prefer_whisper_cpp_for_apple_silicon(FakeDetector(), profile, recommendation)
    assert updated.provider == "voxtral_realtime"
