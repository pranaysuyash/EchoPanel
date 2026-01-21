from dataclasses import dataclass
from typing import Iterable


@dataclass
class ActionItem:
    text: str
    owner: str | None
    due: str | None
    confidence: float


@dataclass
class DecisionItem:
    text: str
    confidence: float


@dataclass
class RiskItem:
    text: str
    confidence: float


@dataclass
class EntityItem:
    name: str
    type: str
    last_seen: float
    confidence: float


def analyze_window(transcript: Iterable[str]) -> dict:
    """
    TODO: Implement analysis cadence for actions, decisions, risks, and entities.
    """
    return {
        "actions": [],
        "decisions": [],
        "risks": [],
        "entities": [],
    }
