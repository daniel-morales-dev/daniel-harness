#!/usr/bin/env python3
"""Tests for dh_data/dynamodb.py — Read operation enforcement."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.dynamodb import validate_read_operation, handle_read

def test_validate_rejects_putitem():
    try:
        validate_read_operation("PutItem")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_rejects_deleteitem():
    try:
        validate_read_operation("DeleteItem")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_rejects_batchwrite():
    try:
        validate_read_operation("BatchWriteItem")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_accepts_getitem():
    validate_read_operation("GetItem")

def test_validate_accepts_query():
    validate_read_operation("Query")

def test_validate_accepts_scan():
    validate_read_operation("Scan")

def test_handle_rejects_putitem():
    result, code = handle_read({}, "", "PutItem", {"tableName": "x"})
    assert code == 2
    assert "error" in result

def test_handle_rejects_deleteitem():
    result, code = handle_read({}, "", "DeleteItem", {"tableName": "x"})
    assert code == 2
    assert "error" in result

def test_handle_rejects_batchwrite():
    result, code = handle_read({}, "", "BatchWriteItem", {"tableName": "x"})
    assert code == 2
    assert "error" in result

def test_handle_no_tablename():
    result, code = handle_read({}, "default", "GetItem", {})
    assert code == 2
    assert "error" in result

if __name__ == "__main__":
    test_validate_rejects_putitem()
    print("[ok] validate_read_operation rechaza PutItem")
    test_validate_rejects_deleteitem()
    print("[ok] validate_read_operation rechaza DeleteItem")
    test_validate_rejects_batchwrite()
    print("[ok] validate_read_operation rechaza BatchWriteItem")
    test_validate_accepts_getitem()
    print("[ok] validate_read_operation acepta GetItem")
    test_validate_accepts_query()
    print("[ok] validate_read_operation acepta Query")
    test_validate_accepts_scan()
    print("[ok] validate_read_operation acepta Scan")
    test_handle_rejects_putitem()
    print("[ok] handle_read rechaza PutItem")
    test_handle_rejects_deleteitem()
    print("[ok] handle_read rechaza DeleteItem")
    test_handle_rejects_batchwrite()
    print("[ok] handle_read rechaza BatchWriteItem")
    test_handle_no_tablename()
    print("[ok] handle_read sin tableName")
    print("\n=== Todos los tests pasaron ===")
