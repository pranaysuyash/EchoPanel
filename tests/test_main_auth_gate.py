from fastapi.testclient import TestClient

from server.main import app


def test_main_endpoints_auth_gate_matches_ws_token(monkeypatch):
    monkeypatch.setenv("ECHOPANEL_WS_AUTH_TOKEN", "secret-token")
    client = TestClient(app)

    # When a token is configured, unauthenticated requests should be rejected.
    assert client.get("/").status_code == 401
    assert client.get("/health").status_code == 401
    assert client.get("/capabilities").status_code == 401
    assert client.get("/model-status").status_code == 401

    # With a valid token, endpoints should respond (status depends on model readiness).
    headers = {"Authorization": "Bearer secret-token"}
    assert client.get("/", headers=headers).status_code == 200
    assert client.get("/health", headers=headers).status_code != 401
    assert client.get("/capabilities", headers=headers).status_code != 401
    assert client.get("/model-status", headers=headers).status_code != 401

