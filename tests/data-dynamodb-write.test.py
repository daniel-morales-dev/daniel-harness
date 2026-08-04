"""Tests for dh_data/dynamodb.py — Write 2-step confirmation with persistent store."""
import os
import tempfile
from pathlib import Path

from dh_data.dynamodb import handle_write
from dh_data.token_store import TokenStore


def setup():
    global _tmpdir, _store
    _tmpdir = Path(tempfile.mkdtemp())
    os.environ["DANIEL_HARNESS_CONFIG_DIR"] = str(_tmpdir)
    _store = TokenStore(_tmpdir / "state")


def teardown():
    import shutil
    shutil.rmtree(str(_tmpdir), ignore_errors=True)


def test_unknown_operation():
    result, code = handle_write({}, "", "unknown", {})
    assert code == 2
    assert "error" in result


def test_prepare_rejects_write_op():
    result, code = handle_write({}, "", "prepare", {"operation": "DeleteItem"})
    assert code == 2
    assert "error" in result


def test_prepare_no_tablename():
    result, code = handle_write({}, "", "prepare", {"operation": "PutItem"})
    assert code == 2
    assert "error" in result


def test_prepare_deny_mode():
    profile = {"writeConfirmation": {"mode": "deny"}}
    result, code = handle_write(profile, "", "prepare", {"operation": "PutItem", "tableName": "x"})
    assert code == 2
    assert "error" in result


def test_confirm_no_token():
    result, code = handle_write({}, "", "confirm", {})
    assert code == 4
    assert "error" in result


def test_confirm_invalid_token():
    result, code = handle_write({}, "", "confirm", {"token": "nonexistent", "tableName": "x"})
    assert code == 4
    assert "error" in result


def test_confirm_expired():
    token = _store.create({"tableName": "x"})
    # Manually set expiry in the past
    path = _store._path(token)
    import json, time
    path.write_text(json.dumps({"payload": {"tableName": "x"}, "expires_at": time.time() - 10}))
    result, code = handle_write({}, "", "confirm", {"token": token, "tableName": "x"})
    assert code == 4
    assert "error" in result


def test_confirm_payload_mismatch():
    token = _store.create({"tableName": "original", "keys": {"id": "1"}})
    result, code = handle_write({}, "", "confirm", {"token": token, "tableName": "different", "keys": {"id": "2"}})
    assert code == 4
    assert "error" in result


def test_confirm_replay():
    token = _store.create({"tableName": "x"})
    handle_write({}, "", "confirm", {"token": token, "tableName": "x"})
    result, code = handle_write({}, "", "confirm", {"token": token, "tableName": "x"})
    assert code == 4
    assert "error" in result


def test_prepare_create_token():
    profile = {"writeConfirmation": {"mode": "exact-operation"}, "region": "us-east-1"}
    result, code = handle_write(profile, "default", "prepare", {"operation": "PutItem", "tableName": "test-table", "keys": {"pk": {"S": "test"}}})
    assert code == 3
    assert "token" in result
    assert result["confirmationRequired"] is True


if __name__ == "__main__":
    setup()
    test_unknown_operation()
    print("[ok] unknown operation")
    test_prepare_rejects_write_op()
    print("[ok] prepare rejects bad write_op")
    test_prepare_no_tablename()
    print("[ok] prepare no tableName")
    test_prepare_deny_mode()
    print("[ok] prepare deny mode")
    test_confirm_no_token()
    print("[ok] confirm no token")
    test_confirm_invalid_token()
    print("[ok] confirm invalid token")
    test_confirm_expired()
    print("[ok] confirm expired")
    test_confirm_payload_mismatch()
    print("[ok] confirm payload mismatch")
    test_confirm_replay()
    print("[ok] confirm replay rejected")
    test_prepare_create_token()
    print("[ok] prepare creates token")
    teardown()
    print("\n=== Todos los tests pasaron ===")
