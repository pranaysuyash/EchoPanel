#!/usr/bin/env python3
import json
from server.services.analysis_stream import extract_entities, extract_cards, generate_rolling_summary

def test_analysis():
    transcript = [
        {"t0": 0.0, "t1": 5.0, "text": "Hello everyone, this is Pranay from EchoPanel.", "source": "mic"},
        {"t0": 5.0, "t1": 10.0, "text": "Today we are discussing the v0.2 launch on Monday.", "source": "mic"},
        {"t0": 10.0, "t1": 20.0, "text": "I will schedule a follow up with Alex to discuss the pricing.", "source": "mic"},
        {"t0": 20.0, "t1": 30.0, "text": "We decided to ship the glass UI polish by Friday.", "source": "system"},
        {"t0": 30.0, "t1": 40.0, "text": "There is a risk that the diarization token might expire.", "source": "system"},
        {"t0": 40.0, "t1": 50.0, "text": "Slack and Zoom integrations are blocked for now.", "source": "mic"},
        {"t0": 50.0, "t1": 60.0, "text": "Dr. Smith will join us for the retrospective.", "source": "mic"},
    ]

    print("--- Entities ---")
    entities = extract_entities(transcript)
    print(json.dumps(entities, indent=2))

    print("\n--- Cards ---")
    cards = extract_cards(transcript)
    print(json.dumps(cards, indent=2))

    print("\n--- Rolling Summary ---")
    summary = generate_rolling_summary(transcript)
    print(summary)

if __name__ == "__main__":
    test_analysis()
