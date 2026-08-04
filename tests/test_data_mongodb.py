"""Tests for dh_data/mongodb.py — Pipeline enforcement with recursive inspection."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.mongodb import validate_pipeline, handle

def test_rejects_out():
    try:
        validate_pipeline([{"$out": "collection"}])
        assert False, "should raise"
    except ValueError:
        pass

def test_rejects_merge():
    try:
        validate_pipeline([{"$merge": {"into": "collection"}}])
        assert False, "should raise"
    except ValueError:
        pass

def test_rejects_where():
    try:
        validate_pipeline([{"$where": "this.field > 5"}])
        assert False, "should raise"
    except ValueError:
        pass

def test_rejects_function():
    try:
        validate_pipeline([{"$function": {"body": "function() {}"}}])
        assert False, "should raise"
    except ValueError:
        pass

def test_rejects_mapreduce():
    try:
        validate_pipeline([{"mapReduce": "collection"}])
        assert False, "should raise"
    except ValueError:
        pass

def test_accepts_match():
    validate_pipeline([{"$match": {"field": "value"}}])

def test_accepts_empty():
    validate_pipeline([])

def test_accepts_none():
    validate_pipeline(None)

def test_rejects_nested_where():
    """Verify $where inside nested expressions is caught."""
    try:
        validate_pipeline([{"$match": {"$expr": {"$function": {"body": "function() { return 1; }"}}}}])
        assert False, "should raise"
    except ValueError:
        pass

def test_rejects_where_in_filter():
    """Verify $where in filter inside $match is caught."""
    try:
        validate_pipeline([{"$match": {"$where": "this.x > 5"}}])
        assert False, "should raise"
    except ValueError:
        pass

def test_handle_unknown_operation():
    result, code = handle({}, "", "write", {"collection": "x"})
    assert code == 2
    assert "error" in result

def test_handle_no_collection():
    result, code = handle({}, "", "find", {})
    assert code == 2
    assert "error" in result

def test_handle_invalid_uri():
    result, code = handle({"database": "test"}, "not-a-uri", "find", {"collection": "x"})
    assert "error" in result
    assert code in (1, 2)  # 1 = pymongo not installed, 2 = invalid URI

if __name__ == "__main__":
    test_rejects_out()
    print("[ok] rejects $out")
    test_rejects_merge()
    print("[ok] rejects $merge")
    test_rejects_where()
    print("[ok] rejects $where")
    test_rejects_function()
    print("[ok] rejects $function")
    test_rejects_mapreduce()
    print("[ok] rejects mapReduce")
    test_accepts_match()
    print("[ok] accepts $match")
    test_accepts_empty()
    print("[ok] accepts empty pipeline")
    test_accepts_none()
    print("[ok] accepts None")
    test_rejects_nested_where()
    print("[ok] rejects nested $function")
    test_rejects_where_in_filter()
    print("[ok] rejects $where in filter")
    test_handle_unknown_operation()
    print("[ok] handle unknown operation")
    test_handle_no_collection()
    print("[ok] handle no collection")
    test_handle_invalid_uri()
    print("[ok] handle invalid URI")
    print("\n=== Todos los tests pasaron ===")
