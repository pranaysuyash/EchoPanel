"""
Degrade Ladder (v0.1)

Adaptive performance management for ASR streaming.
Monitors realtime_factor (RTF) and automatically adjusts configuration to maintain performance.

Degrade Levels:
    0 (Normal):     RTF < 0.8    — Optimal performance
    1 (Warning):    RTF 0.8-1.0  — Log warning, increase chunk size
    2 (Degrade):    RTF 1.0-1.2  — Switch to smaller model, disable VAD
    3 (Emergency):  RTF > 1.2    — Drop every other chunk, emit warnings
    4 (Failover):   Provider crash — Switch to fallback provider

Recovery:
    When RTF < 0.7 for 30s, step up one level (if not at level 0)

Usage:
    from server.services.degrade_ladder import DegradeLadder, DegradeLevel
    
    ladder = DegradeLadder(
        provider=current_provider,
        config=current_config,
        fallback_provider=fallback_provider,
    )
    
    # In ASR loop
    rtf = measure_rtf()
    new_level, action = ladder.check(rtf)
    if action:
        apply_action(action)
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Optional, Dict, Any, Callable, List, Tuple

from .asr_providers import ASRConfig, ASRProvider

logger = logging.getLogger(__name__)


class DegradeLevel(IntEnum):
    """Degradation levels from normal to emergency."""
    NORMAL = 0      # RTF < 0.8 — Optimal
    WARNING = 1     # RTF 0.8-1.0 — Concern
    DEGRADE = 2     # RTF 1.0-1.2 — Action required
    EMERGENCY = 3   # RTF > 1.2 — Critical
    FAILOVER = 4    # Provider failed — Switch provider


@dataclass
class DegradeThresholds:
    """RTF thresholds for degrade levels."""
    warning: float = 0.8
    degrade: float = 1.0
    emergency: float = 1.2
    recovery: float = 0.7  # RTF must be below this for recovery


@dataclass
class DegradeAction:
    """Action to take when degrading or recovering."""
    name: str
    description: str
    apply: Callable[[], None]  # Function to apply the action
    revert: Optional[Callable[[], None]] = None  # Function to revert


@dataclass
class DegradeState:
    """Current state of the degrade ladder."""
    level: DegradeLevel = DegradeLevel.NORMAL
    rtf_history: List[Tuple[float, float]] = field(default_factory=list)  # (timestamp, rtf)
    level_since: float = field(default_factory=time.time)
    actions_applied: List[str] = field(default_factory=list)
    dropped_chunks: int = 0
    last_recovery_check: float = field(default_factory=time.time)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "level": self.level.name,
            "level_since": self.level_since,
            "current_rtf": self.rtf_history[-1][1] if self.rtf_history else 0.0,
            "rtf_avg_10s": self._avg_rtf(10.0),
            "actions_applied": self.actions_applied,
            "dropped_chunks": self.dropped_chunks,
        }
    
    def _avg_rtf(self, window_seconds: float) -> float:
        """Average RTF over the last N seconds."""
        now = time.time()
        recent = [rtf for ts, rtf in self.rtf_history if now - ts < window_seconds]
        if not recent:
            return 0.0
        return sum(recent) / len(recent)


class DegradeLadder:
    """Adaptive performance management for ASR streaming.
    
    Monitors realtime_factor and automatically adjusts ASR configuration
    to maintain acceptable performance under varying load conditions.
    """
    
    # History window for RTF calculation
    HISTORY_WINDOW_S = 60.0
    
    # Time before considering recovery (must be below threshold for this long)
    RECOVERY_WINDOW_S = 30.0
    
    # Minimum time at a level before allowing degrade
    MIN_LEVEL_TIME_S = 10.0

    def __init__(
        self,
        provider: ASRProvider,
        config: ASRConfig,
        fallback_provider: Optional[ASRProvider] = None,
        thresholds: Optional[DegradeThresholds] = None,
        on_level_change: Optional[Callable[[DegradeLevel, DegradeLevel, Optional[DegradeAction]], None]] = None,
    ):
        """Initialize the degrade ladder.
        
        Args:
            provider: Current ASR provider
            config: Current ASR configuration
            fallback_provider: Provider to switch to on FAILOVER
            thresholds: RTF thresholds for level changes
            on_level_change: Callback when level changes
        """
        self.provider = provider
        self.config = config
        self.fallback_provider = fallback_provider
        self.thresholds = thresholds or DegradeThresholds()
        self.on_level_change = on_level_change
        
        self.state = DegradeState()
        self._lock = asyncio.Lock()
        
        # Define actions for each level transition
        self._actions = self._build_actions()
        
        logger.info(f"DegradeLadder initialized at level {self.state.level.name}")

    def _build_actions(self) -> Dict[Tuple[DegradeLevel, DegradeLevel], DegradeAction]:
        """Build the action map for level transitions."""
        actions = {}
        
        # NORMAL -> WARNING: Increase chunk size
        actions[(DegradeLevel.NORMAL, DegradeLevel.WARNING)] = DegradeAction(
            name="increase_chunk_size",
            description="Increase chunk size to reduce inference frequency",
            apply=self._action_increase_chunk_size,
            revert=self._action_decrease_chunk_size,
        )
        
        # WARNING -> DEGRADE: Switch to smaller model, disable VAD
        actions[(DegradeLevel.WARNING, DegradeLevel.DEGRADE)] = DegradeAction(
            name="reduce_quality",
            description="Switch to smaller model and disable VAD",
            apply=self._action_reduce_quality,
            revert=self._action_restore_quality,
        )
        
        # DEGRADE -> EMERGENCY: Start dropping chunks
        actions[(DegradeLevel.DEGRADE, DegradeLevel.EMERGENCY)] = DegradeAction(
            name="drop_chunks",
            description="Drop every other chunk to catch up",
            apply=self._action_enable_chunk_dropping,
            revert=self._action_disable_chunk_dropping,
        )
        
        # Any -> FAILOVER: Switch provider
        actions[(DegradeLevel.NORMAL, DegradeLevel.FAILOVER)] = DegradeAction(
            name="failover",
            description="Switch to fallback provider",
            apply=self._action_failover,
        )
        actions[(DegradeLevel.WARNING, DegradeLevel.FAILOVER)] = actions[(DegradeLevel.NORMAL, DegradeLevel.FAILOVER)]
        actions[(DegradeLevel.DEGRADE, DegradeLevel.FAILOVER)] = actions[(DegradeLevel.NORMAL, DegradeLevel.FAILOVER)]
        actions[(DegradeLevel.EMERGENCY, DegradeLevel.FAILOVER)] = actions[(DegradeLevel.NORMAL, DegradeLevel.FAILOVER)]
        
        return actions

    async def check(self, rtf: float) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
        """Check RTF and return appropriate degrade level and action.
        
        Args:
            rtf: Current realtime_factor (inference_time / audio_time)
        
        Returns:
            Tuple of (current_level, action_to_apply or None)
        """
        async with self._lock:
            now = time.time()
            
            # Record RTF in history
            self.state.rtf_history.append((now, rtf))
            
            # Prune old history
            cutoff = now - self.HISTORY_WINDOW_S
            self.state.rtf_history = [
                (ts, r) for ts, r in self.state.rtf_history if ts > cutoff
            ]
            
            # Determine target level based on RTF
            target_level = self._rtf_to_level(rtf)
            
            # Check if we should change level
            if target_level > self.state.level:
                # Degrading — check minimum time at current level
                time_at_level = now - self.state.level_since
                if time_at_level < self.MIN_LEVEL_TIME_S:
                    logger.debug(f"Want to degrade to {target_level.name} but only at current level for {time_at_level:.1f}s")
                    return self.state.level, None
                
                return await self._degrade_to(target_level)
            
            elif target_level < self.state.level:
                # Recovering — check if sustained below threshold
                return await self._maybe_recover(target_level)
            
            return self.state.level, None

    def _rtf_to_level(self, rtf: float) -> DegradeLevel:
        """Convert RTF to degrade level."""
        if rtf >= self.thresholds.emergency:
            return DegradeLevel.EMERGENCY
        elif rtf >= self.thresholds.degrade:
            return DegradeLevel.DEGRADE
        elif rtf >= self.thresholds.warning:
            return DegradeLevel.WARNING
        else:
            return DegradeLevel.NORMAL

    async def _degrade_to(self, target_level: DegradeLevel) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
        """Degrade to a lower performance level."""
        old_level = self.state.level
        
        # Get action for this transition
        action_key = (old_level, target_level)
        action = self._actions.get(action_key)
        
        # Update state
        self.state.level = target_level
        self.state.level_since = time.time()
        
        if action:
            self.state.actions_applied.append(action.name)
            logger.warning(f"DEGRADE: {old_level.name} -> {target_level.name}: {action.description}")
            
            # Apply action (in executor if blocking)
            if asyncio.iscoroutinefunction(action.apply):
                await action.apply()
            else:
                await asyncio.get_event_loop().run_in_executor(None, action.apply)
        else:
            logger.warning(f"DEGRADE: {old_level.name} -> {target_level.name} (no action defined)")
        
        # Notify callback
        if self.on_level_change:
            if asyncio.iscoroutinefunction(self.on_level_change):
                await self.on_level_change(old_level, target_level, action)
            else:
                self.on_level_change(old_level, target_level, action)
        
        return target_level, action

    async def _maybe_recover(self, target_level: DegradeLevel) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
        """Check if we can recover to a higher performance level."""
        now = time.time()
        
        # Check if RTF has been below recovery threshold for long enough
        if now - self.state.last_recovery_check < self.RECOVERY_WINDOW_S:
            return self.state.level, None
        
        # Check average RTF over recovery window
        recent_rtfs = [
            rtf for ts, rtf in self.state.rtf_history
            if now - ts < self.RECOVERY_WINDOW_S
        ]
        
        if not recent_rtfs:
            return self.state.level, None
        
        avg_rtf = sum(recent_rtfs) / len(recent_rtfs)
        
        if avg_rtf >= self.thresholds.recovery:
            logger.debug(f"RTF avg {avg_rtf:.2f} above recovery threshold {self.thresholds.recovery}")
            return self.state.level, None
        
        # Can recover — step up one level at a time
        new_level = DegradeLevel(self.state.level - 1)
        old_level = self.state.level
        
        self.state.level = new_level
        self.state.level_since = now
        self.state.last_recovery_check = now
        
        # Find revert action for the last applied action
        action_key = (new_level, old_level)
        action = self._actions.get(action_key)
        
        if action and action.revert:
            logger.info(f"RECOVER: {old_level.name} -> {new_level.name}: Reverting {action.name}")
            
            if asyncio.iscoroutinefunction(action.revert):
                await action.revert()
            else:
                await asyncio.get_event_loop().run_in_executor(None, action.revert)
        else:
            logger.info(f"RECOVER: {old_level.name} -> {new_level.name}")
        
        # Notify callback
        if self.on_level_change:
            if asyncio.iscoroutinefunction(self.on_level_change):
                await self.on_level_change(old_level, new_level, None)
            else:
                self.on_level_change(old_level, new_level, None)
        
        return new_level, None

    def should_drop_chunk(self) -> bool:
        """Check if we should drop the current chunk (EMERGENCY level)."""
        if self.state.level < DegradeLevel.EMERGENCY:
            return False
        
        # Drop every other chunk
        self.state.dropped_chunks += 1
        return self.state.dropped_chunks % 2 == 0

    async def report_provider_error(self, error: Exception) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
        """Report a provider error, potentially triggering FAILOVER."""
        logger.error(f"Provider error: {error}")
        
        if self.fallback_provider and self.state.level < DegradeLevel.FAILOVER:
            return await self._degrade_to(DegradeLevel.FAILOVER)
        
        return self.state.level, None

    # Action implementations
    
    def _action_increase_chunk_size(self) -> None:
        """Increase chunk size to reduce inference frequency."""
        old_chunk = self.config.chunk_seconds
        new_chunk = min(8, old_chunk + 1)  # Max 8s chunks
        self.config.chunk_seconds = new_chunk
        logger.info(f"Increased chunk size: {old_chunk}s -> {new_chunk}s")

    def _action_decrease_chunk_size(self) -> None:
        """Revert: decrease chunk size."""
        old_chunk = self.config.chunk_seconds
        new_chunk = max(2, old_chunk - 1)  # Min 2s chunks
        self.config.chunk_seconds = new_chunk
        logger.info(f"Decreased chunk size: {old_chunk}s -> {new_chunk}s")

    def _action_reduce_quality(self) -> None:
        """Switch to smaller model and disable VAD."""
        # Model size downgrade map
        model_downgrade = {
            "large-v3": "medium.en",
            "large-v2": "medium.en",
            "medium.en": "small.en",
            "small.en": "base.en",
            "base.en": "tiny.en",
        }
        
        old_model = self.config.model_name
        new_model = model_downgrade.get(old_model, old_model)
        
        if new_model != old_model:
            self.config.model_name = new_model
            logger.info(f"Downgraded model: {old_model} -> {new_model}")
        
        # Disable VAD to save compute
        if self.config.vad_enabled:
            self.config.vad_enabled = False
            logger.info("Disabled VAD to save compute")

    def _action_restore_quality(self) -> None:
        """Revert: restore VAD."""
        if not self.config.vad_enabled:
            self.config.vad_enabled = True
            logger.info("Re-enabled VAD")

    def _action_enable_chunk_dropping(self) -> None:
        """Enable chunk dropping mode."""
        logger.warning("EMERGENCY: Enabling chunk dropping mode (every other chunk will be dropped)")
        self.state.dropped_chunks = 0

    def _action_disable_chunk_dropping(self) -> None:
        """Revert: disable chunk dropping."""
        logger.info("Disabling chunk dropping mode")
        self.state.dropped_chunks = 0

    def _action_failover(self) -> None:
        """Switch to fallback provider."""
        if self.fallback_provider:
            logger.warning(f"FAILOVER: Switching to {self.fallback_provider.name}")
            self.provider = self.fallback_provider
        else:
            logger.error("FAILOVER requested but no fallback provider available")

    def get_status(self) -> Dict[str, Any]:
        """Get current degrade ladder status."""
        return {
            "level": self.state.level.name,
            "level_number": int(self.state.level),
            "current_rtf": self.state.rtf_history[-1][1] if self.state.rtf_history else 0.0,
            "rtf_avg_10s": self.state._avg_rtf(10.0),
            "rtf_avg_60s": self.state._avg_rtf(60.0),
            "actions_applied": self.state.actions_applied,
            "dropped_chunks": self.state.dropped_chunks,
            "time_at_level": time.time() - self.state.level_since,
            "config": {
                "chunk_seconds": self.config.chunk_seconds,
                "model_name": self.config.model_name,
                "vad_enabled": self.config.vad_enabled,
            },
        }


class AdaptiveASRManager:
    """High-level manager that integrates degrade ladder with ASR pipeline.
    
    Usage:
        manager = AdaptiveASRManager(primary_provider, fallback_provider)
        
        async for chunk in audio_stream:
            if manager.should_process(chunk):
                result = await manager.transcribe(chunk)
                yield result
            
            # Periodic health check
            status = manager.get_status()
    """
    
    def __init__(
        self,
        primary_provider: ASRProvider,
        fallback_provider: Optional[ASRProvider] = None,
        config: Optional[ASRConfig] = None,
    ):
        self.config = config or ASRConfig()
        self.ladder = DegradeLadder(
            provider=primary_provider,
            config=self.config,
            fallback_provider=fallback_provider,
            on_level_change=self._on_level_change,
        )
        self._chunk_times: List[Tuple[float, float]] = []  # (timestamp, infer_ms)
    
    def _on_level_change(
        self,
        old_level: DegradeLevel,
        new_level: DegradeLevel,
        action: Optional[DegradeAction],
    ) -> None:
        """Callback when degrade level changes."""
        action_name = action.name if action else "none"
        logger.info(f"Degrade level change: {old_level.name} -> {new_level.name} (action: {action_name})")
    
    async def process_chunk(self, audio_bytes: bytes, sample_rate: int = 16000) -> Optional[Any]:
        """Process a chunk with degrade ladder monitoring.
        
        Returns:
            Transcription result or None if chunk was dropped.
        """
        # Check if we should drop this chunk
        if self.ladder.should_drop_chunk():
            logger.debug("Dropping chunk due to EMERGENCY level")
            return None
        
        # Process chunk and measure time
        t0 = time.perf_counter()
        
        # Get current provider
        provider = self.ladder.provider
        
        # Transcribe (this would be the actual transcription call)
        # For now, we just measure the time placeholder
        # In real usage, this would call provider.transcribe_chunk() or similar
        
        infer_s = time.perf_counter() - t0
        infer_ms = infer_s * 1000
        
        # Calculate RTF (assume 4s chunks default)
        chunk_seconds = self.config.chunk_seconds
        rtf = infer_s / chunk_seconds
        
        # Record and check degrade ladder
        self._chunk_times.append((time.time(), infer_ms))
        
        # Prune old timings
        cutoff = time.time() - 60
        self._chunk_times = [(t, ms) for t, ms in self._chunk_times if t > cutoff]
        
        # Check degrade ladder
        level, action = await self.ladder.check(rtf)
        
        # Return placeholder result
        return {
            "rtf": rtf,
            "level": level.name,
            "infer_ms": infer_ms,
        }
    
    def should_process(self) -> bool:
        """Check if we should process the next chunk or drop it."""
        return not self.ladder.should_drop_chunk()
    
    def get_status(self) -> Dict[str, Any]:
        """Get current status including degrade ladder state."""
        status = self.ladder.get_status()
        
        # Add recent performance stats
        if self._chunk_times:
            recent_ms = [ms for _, ms in self._chunk_times[-10:]]
            status["recent_avg_ms"] = sum(recent_ms) / len(recent_ms)
        
        return status


if __name__ == "__main__":
    # Demo mode
    logging.basicConfig(level=logging.INFO)
    
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
    
    from server.services.asr_providers import ASRConfig
    
    print("=" * 60)
    print("Degrade Ladder Demo")
    print("=" * 60)
    
    config = ASRConfig(model_name="small.en", device="cpu", compute_type="int8")
    
    # Create mock provider
    class MockProvider:
        name = "mock"
    
    ladder = DegradeLadder(
        provider=MockProvider(),
        config=config,
    )
    
    # Simulate RTF measurements
    test_rtfs = [
        0.5, 0.6, 0.7,  # Normal
        0.85, 0.9,      # Warning
        1.05, 1.1,      # Degrade
        1.3, 1.4,       # Emergency
        1.2, 1.1,       # Still emergency
        0.9, 0.8,       # Degrade
        0.6, 0.5,       # Warning (recovery)
        0.4, 0.3,       # Normal (recovery)
    ]
    
    async def demo():
        for rtf in test_rtfs:
            level, action = await ladder.check(rtf)
            action_str = f" -> {action.name}" if action else ""
            print(f"RTF={rtf:.2f}: {level.name}{action_str}")
            await asyncio.sleep(0.5)
        
        print("\n" + "=" * 60)
        print("Final Status:")
        print("=" * 60)
        import json
        print(json.dumps(ladder.get_status(), indent=2))
    
    asyncio.run(demo())
