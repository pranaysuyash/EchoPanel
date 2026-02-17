"""
SmolVLM Pipeline for EchoPanel

Vision-Language Model for semantic slide understanding.
Uses Hugging Face SmolVLM-256M for contextual OCR enrichment.
"""

import asyncio
import logging
import os
import re
import time
from dataclasses import dataclass, field
from typing import List, Optional

import torch
from PIL import Image

logger = logging.getLogger(__name__)

# Configuration
SMOLVLM_ENABLED = os.getenv("ECHOPANEL_SMOLVLM_ENABLED", "true").lower() == "true"
SMOLVLM_MODEL = os.getenv("ECHOPANEL_SMOLVLM_MODEL", "HuggingFaceTB/SmolVLM-256M-Instruct")
SMOLVLM_DEVICE = os.getenv("ECHOPANEL_SMOLVLM_DEVICE", "auto")
SMOLVLM_DTYPE = os.getenv("ECHOPANEL_SMOLVLM_DTYPE", "bfloat16")
SMOLVLM_MAX_TOKENS = int(os.getenv("ECHOPANEL_SMOLVLM_MAX_TOKENS", "300"))

try:
    from transformers import AutoProcessor, AutoModelForVision2Seq
    TRANSFORMERS_AVAILABLE = True
except ImportError:
    TRANSFORMERS_AVAILABLE = False
    logger.warning("Transformers not installed")


@dataclass
class Entity:
    """Extracted entity from slide."""
    text: str
    type: str
    confidence: float


@dataclass
class SmolVLMResult:
    """Result from SmolVLM processing."""
    text: str = ""
    semantic_summary: str = ""
    key_insights: List[str] = field(default_factory=list)
    entities: List[Entity] = field(default_factory=list)
    confidence: float = 0.0
    processing_time_ms: float = 0.0
    error: Optional[str] = None
    
    @property
    def success(self) -> bool:
        return self.error is None
    
    def to_enriched_text(self) -> str:
        parts = [self.text]
        if self.semantic_summary:
            parts.append(f"Context: {self.semantic_summary}")
        if self.key_insights:
            parts.append(f"Insights: {' '.join(self.key_insights)}")
        if self.entities:
            entity_text = ", ".join([f"{e.text} ({e.type})" for e in self.entities])
            parts.append(f"Entities: {entity_text}")
        return "\n".join(parts)


class SmolVLMPipeline:
    """SmolVLM pipeline for semantic slide understanding."""
    
    def __init__(self, model_name=None, device=None, dtype=None, max_tokens=None):
        self.model_name = model_name or SMOLVLM_MODEL
        self.device = device or SMOLVLM_DEVICE
        self.dtype_str = dtype or SMOLVLM_DTYPE
        self.max_tokens = max_tokens or SMOLVLM_MAX_TOKENS
        self._model = None
        self._processor = None
        self._initialized = False
        self._stats = {
            "frames_processed": 0,
            "frames_failed": 0,
            "total_processing_time_ms": 0,
            "total_tokens_generated": 0,
        }
        self._initialize()
    
    def _initialize(self):
        if not TRANSFORMERS_AVAILABLE or not SMOLVLM_ENABLED:
            return
        try:
            if self.device == "auto":
                if torch.backends.mps.is_available():
                    self.device = "mps"
                elif torch.cuda.is_available():
                    self.device = "cuda"
                else:
                    self.device = "cpu"
            
            if self.dtype_str == "bfloat16":
                self.dtype = torch.bfloat16
            elif self.dtype_str == "float16":
                self.dtype = torch.float16
            else:
                self.dtype = torch.float32
            
            logger.info(f"Loading SmolVLM: {self.model_name} on {self.device}")
            
            self._processor = AutoProcessor.from_pretrained(
                self.model_name, trust_remote_code=True
            )
            self._model = AutoModelForVision2Seq.from_pretrained(
                self.model_name,
                torch_dtype=self.dtype,
                trust_remote_code=True,
                low_cpu_mem_usage=True
            ).to(self.device)
            
            self._initialized = True
            logger.info(f"SmolVLM loaded on {self.device}")
        except Exception as e:
            logger.error(f"Failed to initialize SmolVLM: {e}")
            self._initialized = False
    
    def is_available(self) -> bool:
        return TRANSFORMERS_AVAILABLE and self._initialized
    
    def _build_prompt(self, paddle_context=None):
        if paddle_context and paddle_context.text:
            ocr_text = paddle_context.text[:500]
            layout_type = getattr(paddle_context, 'detected_layout', 'unknown')
            prompt = f"""OCR detected from {layout_type} slide: "{ocr_text}"

Please:
1. Correct any OCR errors or typos
2. Describe what this slide shows
3. Extract 3-5 key insights or data points
4. Identify any people, companies, metrics, or important entities

Format:
CORRECTED_TEXT: <corrected text>
SUMMARY: <brief description>
INSIGHTS: <bullet points>
ENTITIES: <name (type), name (type), ...>"""
        else:
            prompt = """Extract all text from this slide and provide:
1. The complete corrected text
2. A brief summary of what the slide shows
3. Key insights or important data points
4. Any entities mentioned

Format:
CORRECTED_TEXT: <text>
SUMMARY: <summary>
INSIGHTS: <insights>
ENTITIES: <entities>"""
        return prompt
    
    def _parse_output(self, output: str) -> SmolVLMResult:
        text = ""
        summary = ""
        insights = []
        entities = []
        
        text_match = re.search(r'CORRECTED_TEXT:\s*(.+?)(?=\n\w+:|$)', output, re.DOTALL | re.IGNORECASE)
        if text_match:
            text = text_match.group(1).strip()
        else:
            text = output.strip()
        
        summary_match = re.search(r'SUMMARY:\s*(.+?)(?=\n\w+:|$)', output, re.DOTALL | re.IGNORECASE)
        if summary_match:
            summary = summary_match.group(1).strip()
        
        insights_match = re.search(r'INSIGHTS:\s*(.+?)(?=\n\w+:|$)', output, re.DOTALL | re.IGNORECASE)
        if insights_match:
            insights_text = insights_match.group(1).strip()
            insights = [i.strip('- *').strip() for i in insights_text.split('\n') if i.strip()]
            insights = [i for i in insights if i]
        
        entities_match = re.search(r'ENTITIES:\s*(.+?)(?=\n\w+:|$)', output, re.DOTALL | re.IGNORECASE)
        if entities_match:
            entities_text = entities_match.group(1).strip()
            entity_pattern = r'([^,(]+)\s*\(([^)]+)\)'
            for match in re.finditer(entity_pattern, entities_text):
                name = match.group(1).strip()
                type_ = match.group(2).strip().lower()
                entities.append(Entity(text=name, type=type_, confidence=0.8))
        
        confidence = 0.7
        if summary: confidence += 0.1
        if insights: confidence += 0.1
        if entities: confidence += 0.1
        
        return SmolVLMResult(
            text=text,
            semantic_summary=summary,
            key_insights=insights,
            entities=entities,
            confidence=min(0.95, confidence)
        )
    
    async def process(self, image: Image.Image, paddle_context=None) -> SmolVLMResult:
        start_time = time.time()
        
        if not self.is_available():
            return SmolVLMResult(error="SmolVLM not available")
        
        try:
            prompt = self._build_prompt(paddle_context)
            messages = [{
                "role": "user",
                "content": [{"type": "image"}, {"type": "text", "text": prompt}]
            }]
            
            prompt_text = self._processor.apply_chat_template(messages, add_generation_prompt=True)
            inputs = self._processor(text=prompt_text, images=[image], return_tensors="pt")
            inputs = inputs.to(self.device)
            
            with torch.no_grad():
                generated_ids = self._model.generate(
                    **inputs,
                    max_new_tokens=self.max_tokens,
                    do_sample=False,
                    num_beams=1,
                )
            
            output = self._processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
            result = self._parse_output(output)
            
            processing_time = (time.time() - start_time) * 1000
            self._stats["frames_processed"] += 1
            self._stats["total_processing_time_ms"] += processing_time
            self._stats["total_tokens_generated"] += len(generated_ids[0])
            result.processing_time_ms = processing_time
            
            return result
        except Exception as e:
            logger.error(f"SmolVLM processing error: {e}")
            self._stats["frames_failed"] += 1
            return SmolVLMResult(error=str(e), processing_time_ms=(time.time() - start_time) * 1000)
    
    async def answer_query(self, image: Image.Image, query: str, paddle_context=None) -> str:
        if not self.is_available():
            return "SmolVLM not available"
        try:
            context = f"Detected text: \"{paddle_context.text[:400]}\"\n\n" if paddle_context and paddle_context.text else ""
            prompt = f"""{context}Looking at this slide, answer: {query}

Provide a concise answer based only on what's visible."""
            
            messages = [{
                "role": "user",
                "content": [{"type": "image"}, {"type": "text", "text": prompt}]
            }]
            
            prompt_text = self._processor.apply_chat_template(messages, add_generation_prompt=True)
            inputs = self._processor(text=prompt_text, images=[image], return_tensors="pt").to(self.device)
            
            with torch.no_grad():
                generated_ids = self._model.generate(**inputs, max_new_tokens=150, do_sample=False)
            
            answer = self._processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
            return answer.strip()
        except Exception as e:
            logger.error(f"SmolVLM query error: {e}")
            return f"Error: {e}"
    
    def get_stats(self) -> dict:
        stats = self._stats.copy()
        if stats["frames_processed"] > 0:
            stats["avg_processing_time_ms"] = stats["total_processing_time_ms"] / stats["frames_processed"]
            stats["avg_tokens_per_frame"] = stats["total_tokens_generated"] / stats["frames_processed"]
        else:
            stats["avg_processing_time_ms"] = 0
            stats["avg_tokens_per_frame"] = 0
        return stats
    
    def reset_stats(self):
        self._stats = {
            "frames_processed": 0,
            "frames_failed": 0,
            "total_processing_time_ms": 0,
            "total_tokens_generated": 0,
        }
