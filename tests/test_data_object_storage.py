#!/usr/bin/env python3
"""Tests for dh_data/object_storage.py — Object storage enforcement."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.object_storage import validate_key, handle

def test_validate_key_rejects_empty():
    try:
        validate_key("")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_key_rejects_traversal():
    try:
        validate_key("../etc/passwd")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_key_rejects_abs():
    try:
        validate_key("/etc/passwd")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_key_rejects_traversal_subdir():
    try:
        validate_key("data/../../etc/passwd")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_key_accepts_normal():
    validate_key("data/file.txt")

def test_handle_no_operation():
    result, code = handle({}, "", "write", {"bucket": "x", "key": "y"})
    assert code == 2
    assert "error" in result

def test_handle_no_bucket():
    result, code = handle({}, "", "get-object", {"key": "y"})
    assert code == 2
    assert "error" in result

def test_handle_no_key():
    result, code = handle({}, "", "get-object", {"bucket": "x"})
    assert code == 2
    assert "error" in result

def test_handle_traversal():
    result, code = handle({}, "", "get-object", {"bucket": "x", "key": "../etc/passwd"})
    assert code == 2
    assert "error" in result

if __name__ == "__main__":
    test_validate_key_rejects_empty()
    print("[ok] validate_key rechaza key vacío")
    test_validate_key_rejects_traversal()
    print("[ok] validate_key rechaza path traversal")
    test_validate_key_rejects_abs()
    print("[ok] validate_key rechaza key absoluto")
    test_validate_key_rejects_traversal_subdir()
    print("[ok] validate_key rechaza traversal en subdirectorio")
    test_validate_key_accepts_normal()
    print("[ok] validate_key acepta key normal")
    test_handle_no_operation()
    print("[ok] handle operation no soportada")
    test_handle_no_bucket()
    print("[ok] handle sin bucket")
    test_handle_no_key()
    print("[ok] handle sin key")
    test_handle_traversal()
    print("[ok] handle con path traversal")
    print("\n=== Todos los tests pasaron ===")
