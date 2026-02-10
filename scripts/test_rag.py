#!/usr/bin/env python3
import os
import json
import shutil
from pathlib import Path
from server.services.rag_store import reset_rag_store_for_tests

def test_rag():
    test_dir = Path("./tmp_rag_test")
    if test_dir.exists():
        shutil.rmtree(test_dir)
    test_dir.mkdir(parents=True)
    
    store_path = test_dir / "test_store.json"
    store = reset_rag_store_for_tests(store_path=store_path)
    
    # 1. Index documents
    print("Indexing documents...")
    store.index_document(
        title="EchoPanel Architecture",
        text="EchoPanel is a real-time meeting transcription tool with a Swift macOS client and a Python FastAPI backend. It uses Faster-Whisper for local ASR and pyannote for diarization.",
        source="internal"
    )
    
    store.index_document(
        title="Voxtral Research",
        text="Voxtral is a new multi-modal model from Mistral AI. Voxtral Realtime (4B) is suitable for local real-time transcription. Voxtral V2 is an API-only diarization and transcription model.",
        source="research"
    )
    
    # 2. List documents
    docs = store.list_documents()
    print(f"Listed {len(docs)} documents:")
    for doc in docs:
        print(f" - {doc['title']} ({doc['source']})")
    
    # 3. Query
    print("\nQuerying 'Mistral'...")
    results = store.query("Mistral", top_k=2)
    for res in results:
        print(f" - Match in '{res['title']}': {res['snippet']} (Score: {res['score']})")
        
    print("\nQuerying 'FastAPI backend'...")
    results = store.query("FastAPI backend", top_k=2)
    for res in results:
        print(f" - Match in '{res['title']}': {res['snippet']} (Score: {res['score']})")

    # Cleanup
    shutil.rmtree(test_dir)

if __name__ == "__main__":
    test_rag()
