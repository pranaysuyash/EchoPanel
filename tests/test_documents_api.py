from pathlib import Path

from fastapi.testclient import TestClient

from server.main import app
from server.services.rag_store import reset_rag_store_for_tests


def _setup_store(tmp_path: Path, monkeypatch) -> None:
    store_path = tmp_path / "documents.json"
    monkeypatch.setenv("ECHOPANEL_DOC_STORE_PATH", str(store_path))
    reset_rag_store_for_tests(store_path)


def test_documents_index_query_delete_roundtrip(tmp_path: Path, monkeypatch):
    _setup_store(tmp_path, monkeypatch)
    client = TestClient(app)

    initial = client.get("/documents")
    assert initial.status_code == 200
    assert initial.json()["count"] == 0

    indexed = client.post(
        "/documents/index",
        json={
            "title": "Launch Notes",
            "source": "local-file",
            "text": "EchoPanel launch checklist includes deployment, auth, and pricing validation.",
        },
    )
    assert indexed.status_code == 200
    document = indexed.json()["document"]
    document_id = document["document_id"]

    listed = client.get("/documents")
    assert listed.status_code == 200
    assert listed.json()["count"] == 1

    queried = client.post("/documents/query", json={"query": "pricing auth", "top_k": 5})
    assert queried.status_code == 200
    assert queried.json()["count"] >= 1
    assert queried.json()["results"][0]["document_id"] == document_id

    deleted = client.delete(f"/documents/{document_id}")
    assert deleted.status_code == 200
    assert deleted.json()["deleted"] is True

    missing = client.delete(f"/documents/{document_id}")
    assert missing.status_code == 404


def test_documents_auth_gate_matches_ws_token(tmp_path: Path, monkeypatch):
    _setup_store(tmp_path, monkeypatch)
    monkeypatch.setenv("ECHOPANEL_WS_AUTH_TOKEN", "secret-token")
    client = TestClient(app)

    unauthorized = client.get("/documents")
    assert unauthorized.status_code == 401

    authorized = client.get("/documents", headers={"Authorization": "Bearer secret-token"})
    assert authorized.status_code == 200
