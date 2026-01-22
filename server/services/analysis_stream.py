"""
Analysis Stream (v0.2)

Extracts cards (actions, decisions, risks) and entities from transcript segments.
Implements:
- 10-minute sliding window for analysis
- Entity counts, recency tracking, and deduplication
- Card deduplication by fuzzy text matching
- Rolling summary generation
"""

from __future__ import annotations

import os
import re
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"

# Analysis window in seconds (10 minutes)
ANALYSIS_WINDOW_SECONDS = 600.0


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


def extract_cards(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS) -> dict:
    """
    Extract action, decision, and risk cards from transcript.
    
    Uses 10-minute sliding window, deduplication, and recency sorting.
    """
    windowed = _filter_window(transcript, window_seconds)
    
    actions: List[Card] = []
    decisions: List[Card] = []
    risks: List[Card] = []

    action_keywords = ["i will", "we will", "i'll", "we'll", "todo", "to do", "action item", 
                       "follow up", "next step", "take action", "send", "schedule"]
    decision_keywords = ["decide", "decided", "decision", "agree", "agreed", "approval",
                         "approved", "ship", "launch", "go ahead", "finalize"]
    risk_keywords = ["risk", "issue", "blocker", "concern", "problem", "delay", 
                     "blocked", "at risk", "warning", "danger"]

    for segment in windowed:
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


def extract_entities(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS) -> dict:
    """
    Extract entities from transcript with counts, recency, and deduplication.
    
    Uses 10-minute sliding window.
    """
    windowed = _filter_window(transcript, window_seconds)
    
    # Track entities by (name, type)
    entity_map: Dict[Tuple[str, str], Entity] = {}
    
    common_words = {
        "The", "We", "I", "It", "On", "In", "And", "Or", "For", "To", "A", "An",
        "This", "That", "These", "Those", "Is", "Are", "Was", "Were", "Be", "Been",
        "Have", "Has", "Had", "Do", "Does", "Did", "Will", "Would", "Could", "Should",
        "May", "Might", "Must", "Shall", "Can", "Need", "Dare", "But", "So", "Yet",
        "Okay", "OK", "Yeah", "Yes", "No", "Not", "Just", "Also", "Now", "Then",
        "Here", "There", "When", "Where", "What", "Which", "Who", "How", "Why",
    }
    
    # Day names -> dates
    day_names = {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}
    
    # Known organizations
    known_orgs = {"EchoPanel", "Zoom", "Google", "Microsoft", "Apple", "Amazon", "Slack", 
                  "Teams", "Meet", "Discord", "Notion", "Figma", "Linear", "Jira", "GitHub"}
    
    # Common first names for person detection (Gap 4 fix)
    common_first_names = {
        "John", "James", "Michael", "David", "Robert", "William", "Richard", "Joseph", "Thomas", "Charles",
        "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen",
        "Alex", "Chris", "Sam", "Jordan", "Taylor", "Morgan", "Casey", "Jamie", "Drew", "Pat",
        "Pranay", "Raj", "Amit", "Priya", "Neha", "Arjun", "Ravi", "Sanjay", "Anita", "Kavita",
    }
    
    for segment in windowed:
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
            if first in common_words or last in common_words:
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
            if token in common_words:
                continue
            
            # Classify entity type
            if token in day_names:
                entity_type = "date"
            elif token.lower().startswith("v") and "." in token:
                entity_type = "project"  # Version numbers like v2.0
            elif token in known_orgs:
                entity_type = "org"
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


def generate_rolling_summary(transcript: List[dict], window_seconds: float = ANALYSIS_WINDOW_SECONDS) -> str:
    """
    Generate a brief rolling summary of the conversation.
    
    This is a simple extractive summary based on key sentences.
    """
    windowed = _filter_window(transcript, window_seconds)
    
    if not windowed:
        return "No conversation yet."
    
    # Extract cards for summary content
    cards = extract_cards(windowed)
    entities = extract_entities(windowed)
    
    lines = []
    
    # H10 Fix: Better structure with "Recent" context
    
    # 1. Overall Highlights (from whole session)
    all_decisions = extract_cards(transcript).get("decisions", [])
    if all_decisions:
        lines.append(f"## 🏛 Decisions ({len(all_decisions)})")
        for d in all_decisions[-3:]: # Last 3
            lines.append(f"- {d['text']}")
    
    all_actions = extract_cards(transcript).get("actions", [])
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
