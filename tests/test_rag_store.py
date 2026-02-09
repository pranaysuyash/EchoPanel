from pathlib import Path

from server.services.rag_store import LocalRAGStore


def test_rag_store_index_list_query_delete(tmp_path: Path):
    store = LocalRAGStore(store_path=tmp_path / "rag.json", chunk_words=32, overlap_words=8)

    first = store.index_document(
        title="Project Plan",
        text="EchoPanel launch plan includes pricing, onboarding flow, and deployment runbook.",
        source="notes",
    )
    second = store.index_document(
        title="Security Notes",
        text="Authentication token should be optional locally and required for remote websocket exposure.",
        source="security",
    )

    docs = store.list_documents()
    assert len(docs) == 2
    assert {doc["document_id"] for doc in docs} == {first["document_id"], second["document_id"]}

    results = store.query("deployment pricing", top_k=3)
    assert results
    assert results[0]["document_id"] == first["document_id"]
    assert "pricing" in results[0]["snippet"].lower()

    deleted = store.delete_document(first["document_id"])
    assert deleted is True
    assert store.delete_document("missing-id") is False
    assert len(store.list_documents()) == 1


def test_rag_store_persists_to_disk(tmp_path: Path):
    store_path = tmp_path / "rag.json"
    first = LocalRAGStore(store_path=store_path)
    created = first.index_document(title="Checklist", text="Ship tests docs deploy checklist", source="local")

    second = LocalRAGStore(store_path=store_path)
    docs = second.list_documents()
    assert len(docs) == 1
    assert docs[0]["document_id"] == created["document_id"]
