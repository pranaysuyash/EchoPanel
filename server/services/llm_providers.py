"""
LLM Providers for intelligent transcript analysis.

Provides abstraction for multiple LLM backends (OpenAI, Ollama, etc.)
for extracting structured insights from meeting transcripts.
"""

from __future__ import annotations

import os
import json
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Dict, Optional, Any
from enum import Enum

logger = logging.getLogger(__name__)


class LLMProviderType(Enum):
    """Supported LLM providers."""
    NONE = "none"
    OPENAI = "openai"
    OLLAMA = "ollama"


@dataclass
class LLMConfig:
    """Configuration for LLM provider."""
    provider: LLMProviderType
    api_key: Optional[str] = None
    model: str = "gpt-4o-mini"
    base_url: Optional[str] = None  # For Ollama or custom endpoints
    timeout_seconds: float = 30.0
    max_tokens: int = 2000
    temperature: float = 0.3  # Lower for more consistent extraction


@dataclass
class ExtractedInsight:
    """Single extracted insight from transcript."""
    text: str
    insight_type: str  # "action", "decision", "risk", "entity"
    confidence: float
    speakers: List[str]
    timestamp_range: tuple[float, float]
    evidence_quote: str
    owner: Optional[str] = None
    due_date: Optional[str] = None


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""
    
    def __init__(self, config: LLMConfig):
        self.config = config
    
    @abstractmethod
    async def extract_insights(
        self,
        transcript: List[dict],
        insight_types: List[str] = None,
    ) -> List[ExtractedInsight]:
        """
        Extract insights from transcript.
        
        Args:
            transcript: List of transcript segments
            insight_types: Types to extract (action, decision, risk, entity)
        
        Returns:
            List of extracted insights
        """
        pass
    
    @abstractmethod
    async def generate_summary(
        self,
        transcript: List[dict],
        max_length: int = 500,
    ) -> str:
        """Generate meeting summary."""
        pass
    
    @property
    @abstractmethod
    def is_available(self) -> bool:
        """Check if provider is properly configured and available."""
        pass
    
    @property
    @abstractmethod
    def name(self) -> str:
        """Provider name."""
        pass


class OpenAIProvider(LLMProvider):
    """OpenAI GPT provider for analysis."""
    
    def __init__(self, config: LLMConfig):
        super().__init__(config)
        self._client = None
        self._setup_client()
    
    def _setup_client(self):
        """Initialize OpenAI client."""
        try:
            import openai
            api_key = self.config.api_key or os.getenv("OPENAI_API_KEY")
            if api_key:
                self._client = openai.AsyncOpenAI(
                    api_key=api_key,
                    base_url=self.config.base_url,
                    timeout=self.config.timeout_seconds,
                )
        except ImportError:
            logger.warning("OpenAI package not installed")
        except Exception as e:
            logger.error(f"Failed to setup OpenAI client: {e}")
    
    @property
    def name(self) -> str:
        return f"openai_{self.config.model}"
    
    @property
    def is_available(self) -> bool:
        return self._client is not None
    
    def _build_extraction_prompt(
        self,
        transcript: List[dict],
        insight_types: List[str],
    ) -> str:
        """Build prompt for insight extraction."""
        # Format transcript
        transcript_text = "\n".join([
            f"[{seg.get('speaker', 'Unknown')}]: {seg.get('text', '')}"
            for seg in transcript
        ])
        
        types_str = ", ".join(insight_types)
        
        prompt = f"""Analyze this meeting transcript and extract structured insights.

Transcript:
{transcript_text}

Extract the following insight types: {types_str}

For each insight, provide:
- text: The exact text of the insight
- type: One of {types_str}
- confidence: 0.0-1.0 score
- speakers: List of speakers involved
- evidence_quote: The exact quote supporting this insight
- owner: Who is responsible (for actions)
- due_date: When it's due (for actions), ISO format

Return ONLY a JSON array of insights. No markdown, no explanations.

Example output:
[
  {{
    "text": "Schedule follow-up meeting with engineering team",
    "type": "action",
    "confidence": 0.95,
    "speakers": ["Alice", "Bob"],
    "evidence_quote": "Alice: We should schedule a follow-up meeting with the engineering team next week.",
    "owner": "Alice",
    "due_date": "2024-02-21"
  }}
]"""
        return prompt
    
    async def extract_insights(
        self,
        transcript: List[dict],
        insight_types: List[str] = None,
    ) -> List[ExtractedInsight]:
        """Extract insights using OpenAI."""
        if not self.is_available:
            logger.warning("OpenAI provider not available")
            return []
        
        insight_types = insight_types or ["action", "decision", "risk"]
        
        try:
            prompt = self._build_extraction_prompt(transcript, insight_types)
            
            response = await self._client.chat.completions.create(
                model=self.config.model,
                messages=[
                    {
                        "role": "system",
                        "content": "You are a meeting analysis assistant. Extract structured insights from transcripts accurately."
                    },
                    {"role": "user", "content": prompt}
                ],
                max_tokens=self.config.max_tokens,
                temperature=self.config.temperature,
                response_format={"type": "json_object"},
            )
            
            content = response.choices[0].message.content
            if not content:
                return []
            
            # Parse JSON response
            data = json.loads(content)
            insights_data = data if isinstance(data, list) else data.get("insights", [])
            
            insights = []
            for item in insights_data:
                try:
                    insight = ExtractedInsight(
                        text=item.get("text", ""),
                        insight_type=item.get("type", "unknown"),
                        confidence=float(item.get("confidence", 0.5)),
                        speakers=item.get("speakers", []),
                        timestamp_range=(0.0, 0.0),  # Will be filled by caller
                        evidence_quote=item.get("evidence_quote", ""),
                        owner=item.get("owner"),
                        due_date=item.get("due_date"),
                    )
                    insights.append(insight)
                except Exception as e:
                    logger.warning(f"Failed to parse insight: {e}")
                    continue
            
            logger.info(f"OpenAI extracted {len(insights)} insights")
            return insights
            
        except Exception as e:
            logger.error(f"OpenAI extraction failed: {e}")
            return []
    
    async def generate_summary(
        self,
        transcript: List[dict],
        max_length: int = 500,
    ) -> str:
        """Generate meeting summary."""
        if not self.is_available:
            return ""
        
        transcript_text = "\n".join([
            f"[{seg.get('speaker', 'Unknown')}]: {seg.get('text', '')}"
            for seg in transcript[-50:]  # Last 50 segments
        ])
        
        try:
            response = await self._client.chat.completions.create(
                model=self.config.model,
                messages=[
                    {
                        "role": "system",
                        "content": f"Summarize this meeting in {max_length} characters or less. Focus on key decisions and actions."
                    },
                    {"role": "user", "content": transcript_text}
                ],
                max_tokens=300,
                temperature=0.3,
            )
            
            return response.choices[0].message.content or ""
            
        except Exception as e:
            logger.error(f"OpenAI summary failed: {e}")
            return ""


class OllamaProvider(LLMProvider):
    """Ollama local LLM provider.
    
    Runs inference locally using Ollama. Recommended models for meeting analysis:
    - llama3.2:3b - Fast, good for basic extraction (~2GB RAM)
    - qwen2.5:7b - Better accuracy, multilingual (~5GB RAM)
    - mistral:7b - Good balance of speed/quality (~5GB RAM)
    """
    
    def __init__(self, config: LLMConfig):
        super().__init__(config)
        self._base_url = config.base_url or "http://localhost:11434"
    
    @property
    def name(self) -> str:
        return f"ollama_{self.config.model}"
    
    @property
    def is_available(self) -> bool:
        """Check if Ollama is running and model is available."""
        try:
            import urllib.request
            import json
            req = urllib.request.Request(
                f"{self._base_url}/api/tags",
                method="GET",
            )
            with urllib.request.urlopen(req, timeout=2) as resp:
                if resp.status != 200:
                    return False
                data = json.loads(resp.read())
                models = [m.get("name", "") for m in data.get("models", [])]
                # Check if requested model (or base name) is available
                model_base = self.config.model.split(":")[0]
                return any(self.config.model in m or model_base in m for m in models)
        except Exception as e:
            logger.debug(f"Ollama availability check failed: {e}")
            return False
    
    def _build_extraction_prompt(
        self,
        transcript: List[dict],
        insight_types: List[str],
    ) -> str:
        """Build prompt for insight extraction."""
        transcript_text = "\n".join([
            f"[{seg.get('speaker', 'Unknown')}]: {seg.get('text', '')}"
            for seg in transcript
        ])
        
        types_str = ", ".join(insight_types)
        
        prompt = f"""Analyze this meeting transcript and extract structured insights.

Transcript:
{transcript_text}

Extract the following insight types: {types_str}

For each insight, provide:
- text: The exact text of the insight
- type: One of {types_str}
- confidence: 0.0-1.0 score
- speakers: List of speakers involved
- evidence_quote: The exact quote supporting this insight
- owner: Who is responsible (for actions)
- due_date: When it's due (for actions), ISO format

Return ONLY a JSON array of insights. No markdown, no explanations.

Example output:
[
  {{
    "text": "Schedule follow-up meeting with engineering team",
    "type": "action",
    "confidence": 0.95,
    "speakers": ["Alice", "Bob"],
    "evidence_quote": "Alice: We should schedule a follow-up meeting with the engineering team next week.",
    "owner": "Alice",
    "due_date": "2024-02-21"
  }}
]"""
        return prompt
    
    async def extract_insights(
        self,
        transcript: List[dict],
        insight_types: List[str] = None,
    ) -> List[ExtractedInsight]:
        """Extract insights using Ollama."""
        if not self.is_available:
            logger.warning("Ollama not available")
            return []
        
        insight_types = insight_types or ["action", "decision", "risk"]
        
        try:
            import aiohttp
            
            prompt = self._build_extraction_prompt(transcript, insight_types)
            
            payload = {
                "model": self.config.model,
                "prompt": prompt,
                "stream": False,
                "format": "json",
                "options": {
                    "temperature": self.config.temperature,
                    "num_predict": self.config.max_tokens,
                }
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self._base_url}/api/generate",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=self.config.timeout_seconds),
                ) as resp:
                    if resp.status != 200:
                        logger.warning(f"Ollama returned {resp.status}")
                        return []
                    
                    data = await resp.json()
                    content = data.get("response", "")
                    
                    if not content:
                        return []
                    
                    # Parse JSON response
                    try:
                        insights_data = json.loads(content)
                        if isinstance(insights_data, dict):
                            insights_data = insights_data.get("insights", [])
                    except json.JSONDecodeError:
                        # Try to extract JSON from markdown code block
                        import re
                        json_match = re.search(r'```(?:json)?\s*([\s\S]*?)\s*```', content)
                        if json_match:
                            try:
                                insights_data = json.loads(json_match.group(1))
                            except:
                                logger.warning(f"Failed to parse Ollama JSON response")
                                return []
                        else:
                            return []
                    
                    insights = []
                    for item in insights_data:
                        try:
                            insight = ExtractedInsight(
                                text=item.get("text", ""),
                                insight_type=item.get("type", "unknown"),
                                confidence=float(item.get("confidence", 0.5)),
                                speakers=item.get("speakers", []),
                                timestamp_range=(0.0, 0.0),
                                evidence_quote=item.get("evidence_quote", ""),
                                owner=item.get("owner"),
                                due_date=item.get("due_date"),
                            )
                            insights.append(insight)
                        except Exception as e:
                            logger.warning(f"Failed to parse Ollama insight: {e}")
                            continue
                    
                    logger.info(f"Ollama extracted {len(insights)} insights")
                    return insights
                    
        except ImportError:
            logger.error("aiohttp not installed, cannot use Ollama provider")
            return []
        except Exception as e:
            logger.error(f"Ollama extraction failed: {e}")
            return []
    
    async def generate_summary(
        self,
        transcript: List[dict],
        max_length: int = 500,
    ) -> str:
        """Generate summary using Ollama."""
        if not self.is_available:
            return ""
        
        transcript_text = "\n".join([
            f"[{seg.get('speaker', 'Unknown')}]: {seg.get('text', '')}"
            for seg in transcript[-50:]
        ])
        
        try:
            import aiohttp
            
            payload = {
                "model": self.config.model,
                "prompt": f"Summarize this meeting in {max_length} characters or less. Focus on key decisions and actions.\n\n{transcript_text}",
                "stream": False,
                "options": {
                    "temperature": 0.3,
                    "num_predict": 300,
                }
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self._base_url}/api/generate",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=self.config.timeout_seconds),
                ) as resp:
                    if resp.status != 200:
                        return ""
                    
                    data = await resp.json()
                    return data.get("response", "")
                    
        except Exception as e:
            logger.error(f"Ollama summary failed: {e}")
            return ""


class LLMProviderRegistry:
    """Registry for LLM providers."""
    
    _providers: Dict[str, type] = {
        "openai": OpenAIProvider,
        "ollama": OllamaProvider,
    }
    
    @classmethod
    def create_provider(cls, config: LLMConfig) -> Optional[LLMProvider]:
        """Create provider from config."""
        if config.provider == LLMProviderType.NONE:
            return None
        
        provider_class = cls._providers.get(config.provider.value)
        if not provider_class:
            logger.error(f"Unknown provider: {config.provider}")
            return None
        
        try:
            return provider_class(config)
        except Exception as e:
            logger.error(f"Failed to create provider: {e}")
            return None
    
    @classmethod
    def get_available_providers(cls) -> List[str]:
        """Get list of available provider types."""
        return list(cls._providers.keys())


def get_llm_config_from_env() -> LLMConfig:
    """Load LLM config from environment variables."""
    provider_str = os.getenv("ECHOPANEL_LLM_PROVIDER", "none").lower()
    
    try:
        provider = LLMProviderType(provider_str)
    except ValueError:
        provider = LLMProviderType.NONE
    
    return LLMConfig(
        provider=provider,
        api_key=os.getenv("ECHOPANEL_OPENAI_API_KEY"),
        model=os.getenv("ECHOPANEL_LLM_MODEL", "gpt-4o-mini"),
        base_url=os.getenv("ECHOPANEL_LLM_BASE_URL"),
        timeout_seconds=float(os.getenv("ECHOPANEL_LLM_TIMEOUT", "30")),
        max_tokens=int(os.getenv("ECHOPANEL_LLM_MAX_TOKENS", "2000")),
        temperature=float(os.getenv("ECHOPANEL_LLM_TEMPERATURE", "0.3")),
    )
