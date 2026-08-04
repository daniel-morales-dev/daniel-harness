#!/usr/bin/env python3
"""Tests for dh_data/dynamodb.py — Write 2-step confirmation."""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.dynamodb import handle_write, TOKEN_STORE

def setup():
    TOKEN_STORE.clear()

def test_handle_write_unknown_operation():
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

def test_confirm_no_token():
    result, code = handle_write({}, "", "confirm", {})
    assert code == 4
    assert "error" in result

def test_confirm_invalid_token():
    result, code = handle_write({}, "", "confirm", {"token": "nonexistent"})
    assert code == 4
    assert "error" in result

def test_confirm_token_expired():
    TOKEN_STORE["expired-token"] = {"payload": {"tableName": "x"}, "expires": time.time() - 10, "operation": "PutItem"}
    result, code = handle_write({}, "", "confirm", {"token": "expired-token", "tableName": "x"})
    assert code == 4
    assert "error" in result

def test_confirm_payload_mismatch():
    TOKEN_STORE["mismatch-token"] = {"payload": {"tableName": "original-table", "keys": {"id": "1"}}, "expires": time.time() + 60, "operation": "PutItem"}
    result, code = handle_write({}, "", "confirm", {"token": "mismatch-token", "tableName": "different-table", "keys": {"id": "2"}})
    assert code == 4
    assert "error" in result

def test_confirm_replay():
    TOKEN_STORE["replay-token"] = {"payload": {"tableName": "x"}, "expires": time.time() + 60, "operation": "PutItem"}
    # First confirm — will fail at boto3 import (no error path check for tableName), 
    # but that's fine — what matters is the token gets popped
    handle_write({}, "", "confirm", {"token": "replay-token", "tableName": "x"})
    # Second confirm — should fail because token is gone
    result, code = handle_write({}, "", "confirm", {"token": "replay-token", "tableName": "x"})
    assert code == 4
    assert "error" in result

if __name__ == "__main__":
    setup()
    test_handle_write_unknown_operation()
    print("[ok] handle_write operation desconocido")
    test_prepare_rejects_write_op()
    print("[ok] prepare rechaza write_op no permitida")
    test_prepare_no_tablename()
    print("[ok] prepare sin tableName")
    test_confirm_no_token()
    print("[ok] confirm sin token")
    test_confirm_invalid_token()
    print("[ok] confirm token inválido")
    test_confirm_token_expired()
    print("[ok] confirm token expirado")
    test_confirm_payload_mismatch()
    print("[ok] confirm payload no coincide")
    test_confirm_replay()
    print("[ok] confirm replay rechazado")
    print("\n=== Todos los tests pasaron ===")
