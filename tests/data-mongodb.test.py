#!/usr/bin/env python3
"""Tests for dh_data/mongodb.py — Pipeline enforcement."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.mongodb import validate_pipeline, handle

def test_validate_pipeline_rejects_out():
    try:
        validate_pipeline([{"$out": "collection"}])
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_pipeline_rejects_merge():
    try:
        validate_pipeline([{"$merge": {"into": "collection"}}])
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_pipeline_rejects_where():
    try:
        validate_pipeline([{"$where": "this.field > 5"}])
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_pipeline_rejects_function():
    try:
        validate_pipeline([{"$function": {"body": "function() {}"}}])
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_pipeline_rejects_mapreduce():
    try:
        validate_pipeline([{"mapReduce": "collection"}])
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_pipeline_accepts_match():
    validate_pipeline([{"$match": {"field": "value"}}])

def test_validate_pipeline_accepts_empty():
    validate_pipeline([])

def test_validate_pipeline_accepts_none():
    validate_pipeline(None)

def test_handle_unknown_operation():
    result, code = handle({}, "", "write", {"collection": "x"})
    assert code == 2
    assert "error" in result

def test_handle_no_collection():
    result, code = handle({}, "", "find", {})
    assert code == 2
    assert "error" in result

if __name__ == "__main__":
    test_validate_pipeline_rejects_out()
    print("[ok] validate_pipeline rechaza $out")
    test_validate_pipeline_rejects_merge()
    print("[ok] validate_pipeline rechaza $merge")
    test_validate_pipeline_rejects_where()
    print("[ok] validate_pipeline rechaza $where")
    test_validate_pipeline_rejects_function()
    print("[ok] validate_pipeline rechaza $function")
    test_validate_pipeline_rejects_mapreduce()
    print("[ok] validate_pipeline rechaza mapReduce")
    test_validate_pipeline_accepts_match()
    print("[ok] validate_pipeline acepta $match")
    test_validate_pipeline_accepts_empty()
    print("[ok] validate_pipeline acepta pipeline vacío")
    test_validate_pipeline_accepts_none()
    print("[ok] validate_pipeline acepta None")
    test_handle_unknown_operation()
    print("[ok] handle operation desconocido")
    test_handle_no_collection()
    print("[ok] handle sin collection")
    print("\n=== Todos los tests pasaron ===")
