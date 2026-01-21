from dataclasses import dataclass
from typing import List

@dataclass
class CardUpdate:
    actions: List[dict]
    decisions: List[dict]
    risks: List[dict]

@dataclass
class EntityUpdate:
    people: List[dict]
    orgs: List[dict]
    dates: List[dict]
    projects: List[dict]
    topics: List[dict]

class AnalysisStreamService:
    """Placeholder analysis service with cadence control."""

    def update_cards(self, transcript_window: List[str]) -> CardUpdate:
        _ = transcript_window
        return CardUpdate(actions=[], decisions=[], risks=[])

    def update_entities(self, transcript_window: List[str]) -> EntityUpdate:
        _ = transcript_window
        return EntityUpdate(people=[], orgs=[], dates=[], projects=[], topics=[])
