"""
Analysis Stream (v0.3)

Extracts cards (actions, decisions, risks) and entities from transcript segments.
Implements:
- 10-minute sliding window for analysis
- Entity counts, recency tracking, and deduplication
- Card deduplication by fuzzy text matching
- Rolling summary generation
- LLM-powered intelligent extraction (when configured)
"""

from __future__ import annotations

import os
import re
import asyncio
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple, Any

DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"

# Analysis window in seconds (10 minutes)
ANALYSIS_WINDOW_SECONDS = 600.0

# LLM integration
try:
    from .llm_providers import (
        LLMProvider, LLMConfig, LLMProviderType,
        LLMProviderRegistry, get_llm_config_from_env,
        ExtractedInsight
    )
    _LLM_AVAILABLE = True
except ImportError:
    _LLM_AVAILABLE = False
    LLMProvider = None
    ExtractedInsight = None

# Lazy-loaded LLM provider instance
_llm_provider: Optional[LLMProvider] = None

def _get_llm_provider() -> Optional[LLMProvider]:
    """Get or initialize LLM provider."""
    global _llm_provider
    if not _LLM_AVAILABLE:
        return None
    if _llm_provider is None:
        config = get_llm_config_from_env()
        if config.provider != LLMProviderType.NONE:
            _llm_provider = LLMProviderRegistry.create_provider(config)
    return _llm_provider


def _use_llm_extraction() -> bool:
    """Check if LLM extraction is enabled."""
    provider = _get_llm_provider()
    return provider is not None and provider.is_available


@dataclass
class Entity:
    """Tracked entity with occurrence count and recency."""
    name: str
    entity_type: str  # "person", "org", "date", "project", "topic"
    count: int = 0
    last_seen: float = 0.0
    first_seen: float = 0.0
    confidence: float = 0.6
    grounding_quotes: List[str] = field(default_factory=list)


@dataclass
class Card:
    """Extracted card (action/decision/risk) with evidence."""
    text: str
    card_type: str  # "action", "decision", "risk"
    t0: float
    t1: float
    confidence: float = 0.6
    owner: Optional[str] = None
    due: Optional[str] = None
    evidence: List[dict] = field(default_factory=list)


def _filter_window(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS) -> List[dict]:
    """Filter transcript to only include segments within the analysis window."""
    if not transcript:
        return []
    
    # Get max timestamp
    max_t1 = max(seg.get("t1", 0.0) for seg in transcript)
    window_start = max(0.0, max_t1 - window_seconds)
    
    return [
        seg for seg in transcript
        if seg.get("t0", 0.0) >= window_start or seg.get("t1", 0.0) >= window_start
    ]


def _fuzzy_match(text1: str, text2: str, threshold: float = 0.7) -> bool:
    """Simple fuzzy matching based on word overlap."""
    words1 = set(text1.lower().split())
    words2 = set(text2.lower().split())
    if not words1 or not words2:
        return False
    intersection = words1 & words2
    union = words1 | words2
    return len(intersection) / len(union) >= threshold


def _deduplicate_cards(cards: List[Card]) -> List[Card]:
    """Remove duplicate cards based on fuzzy text matching."""
    if not cards:
        return []
    
    result = []
    for card in cards:
        is_dupe = False
        for existing in result:
            if _fuzzy_match(card.text, existing.text):
                # Keep the more recent one
                if card.t1 > existing.t1:
                    result.remove(existing)
                    result.append(card)
                is_dupe = True
                break
        if not is_dupe:
            result.append(card)
    
    # Sort by recency (most recent first)
    result.sort(key=lambda c: c.t1, reverse=True)
    return result


def extract_cards(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS, use_llm: bool = True) -> dict:
    """
    Extract action, decision, and risk cards from transcript.
    
    Uses 10-minute sliding window, deduplication, and recency sorting.
    If LLM is configured, uses LLM for intelligent extraction.
    """
    windowed = _filter_window(transcript, window_seconds)
    
    # Always do keyword extraction as baseline
    keyword_cards = _extract_cards_keyword(windowed)
    
    # Try LLM extraction if enabled and available
    if use_llm and _use_llm_extraction():
        try:
            # Run LLM extraction in async context
            llm_cards = asyncio.run(_extract_cards_llm(windowed))
            if llm_cards:
                # Merge LLM with keyword results
                return _merge_llm_with_keyword(llm_cards, keyword_cards)
        except Exception as e:
            if DEBUG:
                import logging
                logging.getLogger(__name__).debug(f"LLM extraction failed: {e}, using keyword fallback")
    
    return keyword_cards


def _extract_cards_keyword(transcript: List[dict]) -> Dict[str, List[dict]]:
    """
    Extract cards using keyword matching.
    This is the fallback method when LLM is not available.
    """
    actions: List[Card] = []
    decisions: List[Card] = []
    risks: List[Card] = []

    action_keywords = ["i will", "we will", "i'll", "we'll", "todo", "to do", "action item", 
                       "follow up", "next step", "take action", "send", "schedule"]
    decision_keywords = ["decide", "decided", "decision", "agree", "agreed", "approval",
                         "approved", "ship", "launch", "go ahead", "finalize"]
    risk_keywords = ["risk", "issue", "blocker", "concern", "problem", "delay", 
                     "blocked", "at risk", "warning", "danger"]

    for segment in transcript:
        text = segment.get("text", "")
        lower = text.lower()
        t0 = segment.get("t0", 0.0)
        t1 = segment.get("t1", 0.0)
        
        if any(kw in lower for kw in action_keywords):
            actions.append(Card(
                text=text,
                card_type="action",
                t0=t0, t1=t1,
                confidence=segment.get("confidence", 0.0),
                evidence=[{"t0": t0, "t1": t1, "quote": text}]
            ))
        
        if any(kw in lower for kw in decision_keywords):
            decisions.append(Card(
                text=text,
                card_type="decision",
                t0=t0, t1=t1,
                confidence=segment.get("confidence", 0.0),
                evidence=[{"t0": t0, "t1": t1, "quote": text}]
            ))
        
        if any(kw in lower for kw in risk_keywords):
            risks.append(Card(
                text=text,
                card_type="risk",
                t0=t0, t1=t1,
                confidence=segment.get("confidence", 0.0),
                evidence=[{"t0": t0, "t1": t1, "quote": text}]
            ))

    # Deduplicate and limit
    actions = _deduplicate_cards(actions)[:7]
    decisions = _deduplicate_cards(decisions)[:7]
    risks = _deduplicate_cards(risks)[:7]

    return {
        "actions": [_card_to_dict(c) for c in actions],
        "decisions": [_card_to_dict(c) for c in decisions],
        "risks": [_card_to_dict(c) for c in risks],
    }


def extract_cards_incremental(transcript: List[dict], last_t1: float, prev_cards: Dict[str, Any], window_seconds: float = ANALYSIS_WINDOW_SECONDS, use_llm: bool = True) -> Tuple[dict, float]:
    """
    Incrementally update card extraction from transcript.
    
    Only processes segments newer than last_t1, merges with previous results.
    Returns (updated_cards_dict, new_last_t1)
    
    Note: LLM extraction is only run periodically (every 30 seconds of new content)
    to avoid excessive API calls. Keyword extraction runs on every update.
    """
    windowed = _filter_window(transcript, window_seconds)
    
    # Find new segments since last analysis
    new_segments = [seg for seg in windowed if seg.get("t1", 0.0) > last_t1]
    
    if not new_segments:
        # No new segments, return previous results
        return prev_cards, last_t1
    
    # Convert previous results back to card lists
    actions = _dict_to_cards(prev_cards.get("actions", []), "action")
    decisions = _dict_to_cards(prev_cards.get("decisions", []), "decision")
    risks = _dict_to_cards(prev_cards.get("risks", []), "risk")
    
    # Always do keyword extraction for responsiveness
    _extract_cards_from_segments_incremental(new_segments, actions, decisions, risks)
    
    # Run LLM extraction periodically (every ~30 seconds of new content)
    new_content_duration = sum(seg.get("t1", 0.0) - seg.get("t0", 0.0) for seg in new_segments)
    should_run_llm = use_llm and _use_llm_extraction() and new_content_duration >= 30
    
    if should_run_llm:
        try:
            llm_cards = asyncio.run(_extract_cards_llm(windowed))
            if llm_cards:
                # Merge LLM insights with keyword results
                # LLM results take precedence, keyword fills gaps
                for card_type in ["actions", "decisions", "risks"]:
                    llm_list = llm_cards.get(card_type, [])
                    if llm_list:
                        # Replace with LLM results for this type
                        if card_type == "actions":
                            actions = _dict_to_cards(llm_list, "action")
                        elif card_type == "decisions":
                            decisions = _dict_to_cards(llm_list, "decision")
                        elif card_type == "risks":
                            risks = _dict_to_cards(llm_list, "risk")
        except Exception as e:
            if DEBUG:
                import logging
                logging.getLogger(__name__).debug(f"Incremental LLM extraction failed: {e}")
    
    # Deduplicate and limit
    actions = _deduplicate_cards(actions)[:7]
    decisions = _deduplicate_cards(decisions)[:7]
    risks = _deduplicate_cards(risks)[:7]
    
    result = {
        "actions": [_card_to_dict(c) for c in actions],
        "decisions": [_card_to_dict(c) for c in decisions],
        "risks": [_card_to_dict(c) for c in risks],
    }
    
    # Update last_t1 to the max t1 of new segments
    new_last_t1 = max(last_t1, max((seg.get("t1", 0.0) for seg in new_segments), default=last_t1))
    
    return result, new_last_t1


def _dict_to_cards(cards_dict: List[dict], card_type: str) -> List[Card]:
    """Convert cards dict list back to Card objects."""
    cards = []
    for card_dict in cards_dict:
        cards.append(Card(
            text=card_dict["text"],
            card_type=card_type,
            t0=card_dict.get("t0", 0.0),
            t1=card_dict.get("t1", 0.0),
            confidence=card_dict.get("confidence", 0.0),
            owner=card_dict.get("owner"),
            due=card_dict.get("due"),
            evidence=card_dict.get("evidence", [])
        ))
    return cards


def _extract_cards_from_segments_incremental(segments: List[dict], actions: List[Card], decisions: List[Card], risks: List[Card]) -> None:
    """Incrementally extract cards from segments into existing lists."""
    
    action_keywords = ["i will", "we will", "i'll", "we'll", "todo", "to do", "action item", 
                       "follow up", "next step", "take action", "send", "schedule"]
    decision_keywords = ["decide", "decided", "decision", "agree", "agreed", "approval",
                         "approved", "ship", "launch", "go ahead", "finalize"]
    risk_keywords = ["risk", "issue", "blocker", "concern", "problem", "delay", 
                     "blocked", "at risk", "warning", "danger"]

    for segment in segments:
        text = segment.get("text", "")
        lower = text.lower()
        t0 = segment.get("t0", 0.0)
        t1 = segment.get("t1", 0.0)
        
        if any(kw in lower for kw in action_keywords):
            actions.append(Card(
                text=text,
                card_type="action",
                t0=t0, t1=t1,
                confidence=segment.get("confidence", 0.0),
                evidence=[{"t0": t0, "t1": t1, "quote": text}]
            ))
        
        if any(kw in lower for kw in decision_keywords):
            decisions.append(Card(
                text=text,
                card_type="decision",
                t0=t0, t1=t1,
                confidence=segment.get("confidence", 0.0),
                evidence=[{"t0": t0, "t1": t1, "quote": text}]
            ))
        
        if any(kw in lower for kw in risk_keywords):
            risks.append(Card(
                text=text,
                card_type="risk",
                t0=t0, t1=t1,
                confidence=segment.get("confidence", 0.0),
                evidence=[{"t0": t0, "t1": t1, "quote": text}]
            ))


def _card_to_dict(card: Card) -> dict:
    """Convert Card dataclass to dict for JSON serialization."""
    result = {
        "text": card.text,
        "confidence": card.confidence,
        "evidence": card.evidence,
    }
    if card.card_type == "action":
        result["owner"] = card.owner
        result["due"] = card.due
    return result


async def _extract_cards_llm(transcript: List[dict]) -> Dict[str, List[dict]]:
    """
    Extract cards using LLM provider.
    
    This provides more intelligent extraction than keyword matching,
    understanding context, nuance, and implied actions.
    """
    provider = _get_llm_provider()
    if not provider or not provider.is_available:
        return {}
    
    try:
        insights = await provider.extract_insights(
            transcript,
            insight_types=["action", "decision", "risk"]
        )
        
        actions = []
        decisions = []
        risks = []
        
        for insight in insights:
            # Create evidence structure
            evidence = [{
                "t0": 0.0,  # Will be filled by caller with segment timestamps
                "t1": 0.0,
                "quote": insight.evidence_quote or insight.text
            }]
            
            card_dict = {
                "text": insight.text,
                "confidence": insight.confidence,
                "evidence": evidence,
            }
            
            if insight.insight_type == "action":
                card_dict["owner"] = insight.owner
                card_dict["due"] = insight.due_date
                actions.append(card_dict)
            elif insight.insight_type == "decision":
                decisions.append(card_dict)
            elif insight.insight_type == "risk":
                risks.append(card_dict)
        
        return {
            "actions": actions,
            "decisions": decisions,
            "risks": risks,
        }
        
    except Exception as e:
        if DEBUG:
            import logging
            logging.getLogger(__name__).warning(f"LLM extraction failed: {e}")
        return {}


def _merge_llm_with_keyword(
    llm_cards: Dict[str, List[dict]],
    keyword_cards: Dict[str, List[dict]]
) -> Dict[str, List[dict]]:
    """
    Merge LLM and keyword extraction results.
    
    Strategy: Use LLM results preferentially, fall back to keyword
    for any missing categories or low-confidence results.
    """
    result = {}
    
    for card_type in ["actions", "decisions", "risks"]:
        llm_list = llm_cards.get(card_type, [])
        keyword_list = keyword_cards.get(card_type, [])
        
        if llm_list:
            # Use LLM results if available
            result[card_type] = llm_list[:7]
        else:
            # Fall back to keyword extraction
            result[card_type] = keyword_list[:7]
    
    return result


def extract_entities(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS) -> dict:
    """
    Extract entities from transcript with counts, recency, and deduplication.
    
    Uses 10-minute sliding window.
    """
    windowed = _filter_window(transcript, window_seconds)
    return _extract_entities_from_segments(windowed)


def _extract_entities_from_segments(segments: List[dict]) -> dict:
    """Extract entities from a list of transcript segments."""

    def canonicalize_token(token: str) -> str:
        # Strip common punctuation around tokens but preserve internal dots for versions (v2.0).
        cleaned = token.strip().strip(".,:;!?()[]{}\"“”'`")
        # Normalize possessive suffix
        if cleaned.endswith("'s"):
            cleaned = cleaned[:-2]
        if cleaned.endswith("’s"):
            cleaned = cleaned[:-2]
        return cleaned

    def canonicalize_known_org(token: str, known_orgs: set[str]) -> str:
        # Case-insensitive match against known org list to return canonical casing.
        lower_to_canonical = {org.lower(): org for org in known_orgs}
        return lower_to_canonical.get(token.lower(), token)
    
    # Track entities by (name, type)
    entity_map: Dict[Tuple[str, str], Entity] = {}
    
    # Common capitalized tokens that should NOT become "topics".
    # This list intentionally includes pronouns and discourse markers that ASR frequently
    # capitalizes at sentence starts (e.g., "You", "Well", "Alright").
    common_words = {
        "A", "An", "And", "Are", "As", "At",
        "Be", "Been", "But", "By",
        "Can", "Could",
        "Did", "Do", "Does", "Done",
        "For", "From",
        "Had", "Has", "Have", "Here", "How",
        "I", "If", "In", "Into", "Is", "It",
        "Just",
        "May", "Might", "Must", "My",
        "No", "Not", "Now",
        "Of", "On", "Or", "Our", "Out",
        "So", "Should", "Shall",
        "That", "The", "Then", "There", "These", "This", "Those", "To",
        "We", "Were", "What", "When", "Where", "Which", "Who", "Why", "Will", "Would",
        "You", "Your",
        # Discourse / filler
        "Alright", "Okay", "Ok", "OK", "Yeah", "Yes", "Well", "Great", "Thanks", "Thank",
        "Hello", "Hi",
    }
    common_words_lower = {w.lower() for w in common_words}
    
    # Day names -> dates
    day_names = {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}
    
    # Known organizations
    known_orgs = {"EchoPanel", "Zoom", "Google", "Microsoft", "Apple", "Amazon", "Slack", 
                  "Teams", "Meet", "Discord", "Notion", "Figma", "Linear", "Jira", "GitHub"}
    known_orgs_lower = {o.lower() for o in known_orgs}
    
    # Common first names for person detection (Gap 4 fix)
    common_first_names = {
        "John", "James", "Michael", "David", "Robert", "William", "Richard", "Joseph", "Thomas", "Charles",
        "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen",
        "Alex", "Chris", "Sam", "Jordan", "Taylor", "Morgan", "Casey", "Jamie", "Drew", "Pat",
        "Pranay", "Raj", "Amit", "Priya", "Neha", "Arjun", "Ravi", "Sanjay", "Anita", "Kavita",
    }
    
    for segment in segments:
        text = segment.get("text", "")
        t1 = segment.get("t1", 0.0)
        t0 = segment.get("t0", 0.0)
        
        # Gap 4 fix: Detect person names with titles (Mr./Mrs./Ms./Dr.)
        title_pattern = r"\b(Mr\.|Mrs\.|Ms\.|Dr\.)\s+([A-Z][a-z]+)"
        title_matches = re.findall(title_pattern, text)
        for title, name in title_matches:
            full_name = f"{title} {name}"
            key = (full_name, "person")
            if key not in entity_map:
                entity_map[key] = Entity(
                    name=full_name,
                    entity_type="person",
                    count=0,
                    first_seen=t0,
                    last_seen=t1,
                    grounding_quotes=[],
                )
            entity = entity_map[key]
            entity.count += 1
            entity.last_seen = max(entity.last_seen, t1)
            if len(entity.grounding_quotes) < 3:
                entity.grounding_quotes.append(text[:100])
        
        # Gap 4 fix: Detect two-word capitalized names (likely person names)
        two_word_pattern = r"\b([A-Z][a-z]+)\s+([A-Z][a-z]+)\b"
        two_word_matches = re.findall(two_word_pattern, text)
        for first, last in two_word_matches:
            if first.lower() in common_words_lower or last.lower() in common_words_lower:
                continue
            if first in day_names or last in day_names:
                continue
            if first in known_orgs or last in known_orgs:
                continue
            # Likely a person name
            full_name = f"{first} {last}"
            key = (full_name, "person")
            if key not in entity_map:
                entity_map[key] = Entity(
                    name=full_name,
                    entity_type="person",
                    count=0,
                    first_seen=t0,
                    last_seen=t1,
                    grounding_quotes=[],
                )
            entity = entity_map[key]
            entity.count += 1
            entity.last_seen = max(entity.last_seen, t1)
            if len(entity.grounding_quotes) < 3:
                entity.grounding_quotes.append(text[:100])
        
        # Gap 4 fix: Single common first names
        for first_name in common_first_names:
            if first_name in text:
                key = (first_name, "person")
                if key not in entity_map:
                    entity_map[key] = Entity(
                        name=first_name,
                        entity_type="person",
                        count=0,
                        first_seen=t0,
                        last_seen=t1,
                        grounding_quotes=[],
                    )
                entity = entity_map[key]
                entity.count += 1
                entity.last_seen = max(entity.last_seen, t1)
                if len(entity.grounding_quotes) < 3:
                    entity.grounding_quotes.append(text[:100])
        
        # Extract capitalized tokens (potential named entities)
        tokens = re.findall(r"\b[A-Z][a-zA-Z0-9\.]+\b", text)
        
        for token in tokens:
            token = canonicalize_token(token)
            if not token:
                continue
            # Filter noisy "topic" candidates (pronouns, fillers, etc.)
            if token.lower() in common_words_lower:
                continue
            if len(token) < 3:
                continue
            
            # Classify entity type
            if token in day_names:
                entity_type = "date"
            elif token.lower().startswith("v") and "." in token:
                entity_type = "project"  # Version numbers like v2.0
            elif token.lower() in known_orgs_lower:
                entity_type = "org"
                token = canonicalize_known_org(token, known_orgs)
            else:
                entity_type = "topic"
            
            key = (token, entity_type)
            if key not in entity_map:
                entity_map[key] = Entity(
                    name=token,
                    entity_type=entity_type,
                    count=0,
                    first_seen=t0,
                    last_seen=t1,
                    grounding_quotes=[],
                )
            
            entity = entity_map[key]
            entity.count += 1
            entity.last_seen = max(entity.last_seen, t1)
            if len(entity.grounding_quotes) < 3:  # Keep up to 3 quotes for grounding
                entity.grounding_quotes.append(text[:100])  # Truncate long quotes
    
    # Convert to lists, sorted by count (desc) then recency (desc)
    def sort_key(e: Entity) -> Tuple[int, float]:
        return (-e.count, -e.last_seen)
    
    people = sorted([e for e in entity_map.values() if e.entity_type == "person"], key=sort_key)
    orgs = sorted([e for e in entity_map.values() if e.entity_type == "org"], key=sort_key)
    dates = sorted([e for e in entity_map.values() if e.entity_type == "date"], key=sort_key)
    projects = sorted([e for e in entity_map.values() if e.entity_type == "project"], key=sort_key)
    topics = sorted([e for e in entity_map.values() if e.entity_type == "topic"], key=sort_key)

    def _entity_to_dict(e: Entity) -> dict:
        return {
            "name": e.name,
            "type": e.entity_type,
            "count": e.count,
            "last_seen": e.last_seen,
            "confidence": e.confidence,
            "grounding": e.grounding_quotes[:2],  # Include up to 2 grounding quotes
        }

    return {
        "people": [_entity_to_dict(e) for e in people[:7]],
        "orgs": [_entity_to_dict(e) for e in orgs[:7]],
        "dates": [_entity_to_dict(e) for e in dates[:7]],
        "projects": [_entity_to_dict(e) for e in projects[:7]],
        "topics": [_entity_to_dict(e) for e in topics[:12]],  # More topics allowed
    }


def extract_entities_incremental(transcript: List[dict], last_t1: float, prev_entities: Dict[str, Any], window_seconds: float = ANALYSIS_WINDOW_SECONDS) -> Tuple[dict, float]:
    """
    Incrementally update entity extraction from transcript.
    
    Only processes segments newer than last_t1, merges with previous results.
    Returns (updated_entities_dict, new_last_t1)
    """
    windowed = _filter_window(transcript, window_seconds)
    
    # Find new segments since last analysis
    new_segments = [seg for seg in windowed if seg.get("t1", 0.0) > last_t1]
    
    if not new_segments:
        # No new segments, return previous results
        return prev_entities, last_t1
    
    # Convert previous results back to entity_map format for incremental processing
    entity_map = _dict_to_entity_map(prev_entities)
    
    # Process only new segments
    _extract_entities_from_segments_incremental(new_segments, entity_map)
    
    # Convert back to dict format
    result = _entity_map_to_dict(entity_map)
    
    # Update last_t1 to the max t1 of new segments
    new_last_t1 = max(last_t1, max((seg.get("t1", 0.0) for seg in new_segments), default=last_t1))
    
    return result, new_last_t1


def _dict_to_entity_map(entities_dict: Dict[str, Any]) -> Dict[Tuple[str, str], Entity]:
    """Convert entities dict back to entity_map format."""
    entity_map = {}
    for category in ["people", "orgs", "dates", "projects", "topics"]:
        for entity_dict in entities_dict.get(category, []):
            name = entity_dict["name"]
            entity_type = entity_dict["type"]
            key = (name, entity_type)
            entity_map[key] = Entity(
                name=name,
                entity_type=entity_type,
                count=entity_dict["count"],
                last_seen=entity_dict["last_seen"],
                first_seen=entity_dict.get("first_seen", entity_dict["last_seen"]),
                confidence=entity_dict.get("confidence", 0.6),
                grounding_quotes=entity_dict.get("grounding", [])
            )
    return entity_map


def _entity_map_to_dict(entity_map: Dict[Tuple[str, str], Entity]) -> dict:
    """Convert entity_map to dict format."""
    def sort_key(e: Entity) -> Tuple[int, float]:
        return (-e.count, -e.last_seen)
    
    people = sorted([e for e in entity_map.values() if e.entity_type == "person"], key=sort_key)
    orgs = sorted([e for e in entity_map.values() if e.entity_type == "org"], key=sort_key)
    dates = sorted([e for e in entity_map.values() if e.entity_type == "date"], key=sort_key)
    projects = sorted([e for e in entity_map.values() if e.entity_type == "project"], key=sort_key)
    topics = sorted([e for e in entity_map.values() if e.entity_type == "topic"], key=sort_key)

    def _entity_to_dict(e: Entity) -> dict:
        return {
            "name": e.name,
            "type": e.entity_type,
            "count": e.count,
            "last_seen": e.last_seen,
            "confidence": e.confidence,
            "grounding": e.grounding_quotes[:2],
        }

    return {
        "people": [_entity_to_dict(e) for e in people[:7]],
        "orgs": [_entity_to_dict(e) for e in orgs[:7]],
        "dates": [_entity_to_dict(e) for e in dates[:7]],
        "projects": [_entity_to_dict(e) for e in projects[:7]],
        "topics": [_entity_to_dict(e) for e in topics[:12]],
    }


def _extract_entities_from_segments_incremental(segments: List[dict], entity_map: Dict[Tuple[str, str], Entity]) -> None:
    """Incrementally extract entities from segments into existing entity_map."""

    def canonicalize_token(token: str) -> str:
        cleaned = token.strip().strip(".,:;!?()[]{}\"“”'`")
        if cleaned.endswith("'s"):
            cleaned = cleaned[:-2]
        if cleaned.endswith("’s"):
            cleaned = cleaned[:-2]
        return cleaned

    def canonicalize_known_org(token: str, known_orgs: set[str]) -> str:
        lower_to_canonical = {org.lower(): org for org in known_orgs}
        return lower_to_canonical.get(token.lower(), token)
    
    # Common words, day names, orgs, first names - same as before
    common_words = {
        "A", "An", "And", "Are", "As", "At",
        "Be", "Been", "But", "By",
        "Can", "Could",
        "Did", "Do", "Does", "Done",
        "For", "From",
        "Had", "Has", "Have", "Here", "How",
        "I", "If", "In", "Into", "Is", "It",
        "Just",
        "May", "Might", "Must", "My",
        "No", "Not", "Now",
        "Of", "On", "Or", "Our", "Out",
        "So", "Should", "Shall",
        "That", "The", "Then", "There", "These", "This", "Those", "To",
        "We", "Were", "What", "When", "Where", "Which", "Who", "Why", "Will", "Would",
        "You", "Your",
        "Alright", "Okay", "Ok", "OK", "Yeah", "Yes", "Well", "Great", "Thanks", "Thank",
        "Hello", "Hi",
    }
    common_words_lower = {w.lower() for w in common_words}
    
    day_names = {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}
    
    known_orgs = {"EchoPanel", "Zoom", "Google", "Microsoft", "Apple", "Amazon", "Slack", 
                  "Teams", "Meet", "Discord", "Notion", "Figma", "Linear", "Jira", "GitHub"}
    known_orgs_lower = {o.lower() for o in known_orgs}
    
    common_first_names = {
        "John", "James", "Michael", "David", "Robert", "William", "Richard", "Joseph", "Thomas", "Charles",
        "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen",
        "Alex", "Chris", "Sam", "Jordan", "Taylor", "Morgan", "Casey", "Jamie", "Drew", "Pat",
        "Pranay", "Raj", "Amit", "Priya", "Neha", "Arjun", "Ravi", "Sanjay", "Anita", "Kavita",
    }
    
    for segment in segments:
        text = segment.get("text", "")
        t1 = segment.get("t1", 0.0)
        t0 = segment.get("t0", 0.0)
        
        # Same extraction logic as before, but updating existing entity_map
        title_pattern = r"\b(Mr\.|Mrs\.|Ms\.|Dr\.)\s+([A-Z][a-z]+)"
        title_matches = re.findall(title_pattern, text)
        for title, name in title_matches:
            full_name = f"{title} {name}"
            key = (full_name, "person")
            if key not in entity_map:
                entity_map[key] = Entity(
                    name=full_name,
                    entity_type="person",
                    count=0,
                    first_seen=t0,
                    last_seen=t1,
                    grounding_quotes=[],
                )
            entity = entity_map[key]
            entity.count += 1
            entity.last_seen = max(entity.last_seen, t1)
            if len(entity.grounding_quotes) < 3:
                entity.grounding_quotes.append(text[:100])
        
        two_word_pattern = r"\b([A-Z][a-z]+)\s+([A-Z][a-z]+)\b"
        two_word_matches = re.findall(two_word_pattern, text)
        for first, last in two_word_matches:
            if first.lower() in common_words_lower or last.lower() in common_words_lower:
                continue
            if first in day_names or last in day_names:
                continue
            if first in known_orgs or last in known_orgs:
                continue
            full_name = f"{first} {last}"
            key = (full_name, "person")
            if key not in entity_map:
                entity_map[key] = Entity(
                    name=full_name,
                    entity_type="person",
                    count=0,
                    first_seen=t0,
                    last_seen=t1,
                    grounding_quotes=[],
                )
            entity = entity_map[key]
            entity.count += 1
            entity.last_seen = max(entity.last_seen, t1)
            if len(entity.grounding_quotes) < 3:
                entity.grounding_quotes.append(text[:100])
        
        for first_name in common_first_names:
            if first_name in text:
                key = (first_name, "person")
                if key not in entity_map:
                    entity_map[key] = Entity(
                        name=first_name,
                        entity_type="person",
                        count=0,
                        first_seen=t0,
                        last_seen=t1,
                        grounding_quotes=[],
                    )
                entity = entity_map[key]
                entity.count += 1
                entity.last_seen = max(entity.last_seen, t1)
                if len(entity.grounding_quotes) < 3:
                    entity.grounding_quotes.append(text[:100])
        
        tokens = re.findall(r"\b[A-Z][a-zA-Z0-9\.]+\b", text)
        
        for token in tokens:
            token = canonicalize_token(token)
            if not token:
                continue
            if token.lower() in common_words_lower:
                continue
            if len(token) < 3:
                continue
            
            if token in day_names:
                entity_type = "date"
            elif token.lower().startswith("v") and "." in token:
                entity_type = "project"
            elif token.lower() in known_orgs_lower:
                entity_type = "org"
                token = canonicalize_known_org(token, known_orgs)
            else:
                entity_type = "topic"
            
            key = (token, entity_type)
            if key not in entity_map:
                entity_map[key] = Entity(
                    name=token,
                    entity_type=entity_type,
                    count=0,
                    first_seen=t0,
                    last_seen=t1,
                    grounding_quotes=[],
                )
            
            entity = entity_map[key]
            entity.count += 1
            entity.last_seen = max(entity.last_seen, t1)
            if len(entity.grounding_quotes) < 3:
                entity.grounding_quotes.append(text[:100])


async def _generate_summary_llm(transcript: List[dict], max_length: int = 500) -> Optional[str]:
    """
    Generate meeting summary using LLM.
    
    Returns None if LLM is not available.
    """
    provider = _get_llm_provider()
    if not provider or not provider.is_available:
        return None
    
    try:
        return await provider.generate_summary(transcript, max_length)
    except Exception as e:
        if DEBUG:
            import logging
            logging.getLogger(__name__).warning(f"LLM summary failed: {e}")
        return None


def generate_rolling_summary(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS, use_llm: bool = True) -> str:
    """
    Generate a brief rolling summary of the conversation.
    
    This is a simple extractive summary based on key sentences.
    If LLM is configured and use_llm is True, attempts LLM-powered summary.
    """
    windowed = _filter_window(transcript, window_seconds)
    
    if not windowed:
        return "No conversation yet."
    
    # Try LLM summary first if enabled
    if use_llm and _use_llm_extraction():
        try:
            llm_summary = asyncio.run(_generate_summary_llm(windowed, max_length=400))
            if llm_summary:
                return llm_summary
        except Exception:
            pass  # Fall back to keyword-based summary
    
    # Extract cards for summary content
    cards = extract_cards(windowed, use_llm=False)  # Avoid double LLM call
    entities = extract_entities(windowed)
    
    lines = []
    
    # H10 Fix: Better structure with "Recent" context
    
    # 1. Overall Highlights (from whole session)
    all_decisions = extract_cards(transcript, use_llm=False).get("decisions", [])
    if all_decisions:
        lines.append(f"## 🏛 Decisions ({len(all_decisions)})")
        for d in all_decisions[-3:]: # Last 3
            lines.append(f"- {d['text']}")
    
    all_actions = extract_cards(transcript, use_llm=False).get("actions", [])
    if all_actions:
        lines.append(f"\n## ⚡ Action Items ({len(all_actions)})")
        for a in all_actions[-3:]:
             lines.append(f"- {a['text']}")

    # 2. Recent Context (Windowed)
    lines.append(f"\n## 🕒 Recent Context (Last 10m)")
    
    topics = entities.get("topics", [])
    if topics:
        topic_names = [t["name"] for t in topics[:5]]
        lines.append(f"**Topics:** {', '.join(topic_names)}")
    
    risks = cards.get("risks", [])
    if risks:
        for r in risks[:2]:
            lines.append(f"- ⚠️ {r['text']}")

    if not lines:
        return "Waiting for conversation..."
    
    return "\n".join(lines)
