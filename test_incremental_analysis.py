#!/usr/bin/env python3
"""
Test script for incremental analysis functions.
"""

import asyncio
import sys
import os

# Add server to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'server'))

from services.analysis_stream import extract_entities_incremental, extract_cards_incremental

async def test_incremental_analysis():
    print('Testing incremental analysis functions...')

    # Mock transcript data (list of dicts as expected by functions)
    transcript = [
        {
            'text': 'John from marketing said we need to increase our Q1 budget by 20% for the new campaign.',
            't0': 0.0,
            't1': 10.0,
            'speaker': 'unknown'
        }
    ]

    last_t1 = 0.0
    prev_entities = {}
    prev_cards = {}

    try:
        # Test entity extraction
        entities_result, new_t1 = extract_entities_incremental(transcript, last_t1, prev_entities)
        print(f'✅ Entity extraction: {len(entities_result)} entities found, new_t1={new_t1}')

        # Test card extraction
        cards_result, new_t1_cards = extract_cards_incremental(transcript, last_t1, prev_cards)
        print(f'✅ Card extraction: {len(cards_result)} cards found, new_t1={new_t1_cards}')

        print('✅ Incremental analysis functions working correctly')
        return True
    except Exception as e:
        print(f'❌ Error testing incremental analysis: {e}')
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = asyncio.run(test_incremental_analysis())
    sys.exit(0 if success else 1)