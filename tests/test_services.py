from server.services.analysis_stream import extract_cards, extract_entities


def test_extract_cards_empty() -> None:
    cards = extract_cards([])
    assert cards["actions"] == []
    assert cards["decisions"] == []
    assert cards["risks"] == []


def test_extract_entities_empty() -> None:
    entities = extract_entities([])
    assert entities["people"] == []
    assert entities["orgs"] == []
    assert entities["dates"] == []
    assert entities["projects"] == []
    assert entities["topics"] == []
