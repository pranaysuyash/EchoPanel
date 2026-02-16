from server.services.analysis_stream import extract_entities, extract_entities_incremental


def test_extract_entities_normalizes_known_org_punctuation_and_casing() -> None:
    transcript = [
        {"t0": 0.0, "t1": 1.0, "text": "We should check GitHub.", "confidence": 0.9},
        {"t0": 1.0, "t1": 2.0, "text": "Github is down again", "confidence": 0.9},
        {"t0": 2.0, "t1": 3.0, "text": "Ping Zoom, and then GitHub", "confidence": 0.9},
    ]

    entities = extract_entities(transcript)
    org_names = [e["name"] for e in entities.get("orgs", [])]

    assert "GitHub" in org_names
    github = next(e for e in entities["orgs"] if e["name"] == "GitHub")
    assert github["count"] == 3

    assert "Zoom" in org_names
    zoom = next(e for e in entities["orgs"] if e["name"] == "Zoom")
    assert zoom["count"] == 1


def test_extract_entities_incremental_applies_same_normalization() -> None:
    prev_entities = {"people": [], "orgs": [], "dates": [], "projects": [], "topics": []}

    transcript = [
        {"t0": 0.0, "t1": 1.0, "text": "GitHub.", "confidence": 0.9},
        {"t0": 1.0, "t1": 2.0, "text": "Github", "confidence": 0.9},
    ]

    result, last_t1 = extract_entities_incremental(transcript, last_t1=0.0, prev_entities=prev_entities)
    assert last_t1 == 2.0
    orgs = result.get("orgs", [])
    assert any(o["name"] == "GitHub" for o in orgs)
    github = next(o for o in orgs if o["name"] == "GitHub")
    assert github["count"] == 2

