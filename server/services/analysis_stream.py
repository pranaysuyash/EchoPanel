from __future__ import annotations

import re
from typing import Dict, List


def extract_cards(transcript: List[dict]) -> dict:
    actions = []
    decisions = []
    risks = []

    for segment in transcript:
        text = segment.get("text", "")
        lower = text.lower()
        if any(token in lower for token in ["i will", "we will", "todo", "action", "send", "follow up"]):
            actions.append(_make_item(text, segment, item_type="action"))
        if any(token in lower for token in ["decide", "decision", "agree", "ship", "approved"]):
            decisions.append(_make_item(text, segment, item_type="decision"))
        if any(token in lower for token in ["risk", "issue", "blocker", "concern"]):
            risks.append(_make_item(text, segment, item_type="risk"))

    return {
        "actions": actions[:5],
        "decisions": decisions[:5],
        "risks": risks[:5],
    }


def extract_entities(transcript: List[dict]) -> dict:
    people = []
    orgs = []
    dates = []
    projects = []
    topics = []

    common = {"The", "We", "I", "It", "On", "In", "And", "Or", "For"}
    for segment in transcript:
        text = segment.get("text", "")
        tokens = re.findall(r"\\b[A-Z][a-zA-Z0-9\\.]+\\b", text)
        last_seen = segment.get("t1", 0.0)
        for token in tokens:
            if token in common:
                continue
            entry = {"name": token, "last_seen": last_seen, "confidence": 0.6}
            if token in {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday"}:
                dates.append(entry)
            elif token.lower().startswith("v") and "." in token:
                projects.append(entry)
            elif token in {"EchoPanel", "Zoom", "Google", "Microsoft"}:
                orgs.append(entry)
            else:
                topics.append(entry)

    return {
        "people": people[:5],
        "orgs": orgs[:5],
        "dates": dates[:5],
        "projects": projects[:5],
        "topics": topics[:5],
    }


def _make_item(text: str, segment: dict, item_type: str) -> dict:
    item = {
        "text": text,
        "confidence": 0.6,
        "evidence": [
            {"t0": segment.get("t0", 0.0), "t1": segment.get("t1", 0.0), "quote": text}
        ],
    }
    if item_type == "action":
        item["owner"] = None
        item["due"] = None
    return item
