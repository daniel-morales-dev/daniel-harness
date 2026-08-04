#!/usr/bin/env python3
"""Tests for dh_data/mysql.py — SQL enforcement and execution."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.mysql import validate_sql, handle

def test_validate_sql_rejects_insert():
    try:
        validate_sql("INSERT INTO x VALUES (1)")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_sql_rejects_update():
    try:
        validate_sql("UPDATE x SET a=1")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_sql_rejects_delete():
    try:
        validate_sql("DELETE FROM x")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_sql_rejects_drop():
    try:
        validate_sql("DROP TABLE x")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_sql_rejects_into_outfile():
    try:
        validate_sql("SELECT * INTO OUTFILE '/tmp/x' FROM t")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_sql_rejects_load_file():
    try:
        validate_sql("SELECT LOAD_FILE('/etc/passwd')")
    except ValueError:
        pass
    else:
        assert False, "should raise"

def test_validate_sql_rejects_multi_statement():
    try:
        validate_sql("SELECT 1; DROP TABLE x")
        assert False, "should raise"
    except ValueError:
        pass

def test_validate_sql_accepts_select():
    result = validate_sql("SELECT * FROM users WHERE id = 1")
    assert result == "SELECT * FROM users WHERE id = 1"

def test_validate_sql_accepts_show():
    result = validate_sql("SHOW TABLES")
    assert result == "SHOW TABLES"

def test_validate_sql_accepts_describe():
    result = validate_sql("DESCRIBE users")
    assert result == "DESCRIBE users"

def test_validate_sql_accepts_explain():
    result = validate_sql("EXPLAIN SELECT * FROM users")
    assert result == "EXPLAIN SELECT * FROM users"

def test_validate_sql_trailing_semicolon():
    result = validate_sql("SELECT 1;")
    assert result == "SELECT 1"

def test_handle_unknown_operation():
    result, code = handle({}, "", "write", {})
    assert code == 2
    assert "error" in result

def test_handle_empty_sql():
    result, code = handle({}, "", "query", {"sql": ""})
    assert code == 2
    assert "error" in result

def test_handle_policy_violation():
    result, code = handle({}, "", "query", {"sql": "DELETE FROM users"})
    assert code == 2
    assert "error" in result

if __name__ == "__main__":
    test_validate_sql_rejects_insert()
    print("[ok] validate_sql rechaza INSERT")
    test_validate_sql_rejects_update()
    print("[ok] validate_sql rechaza UPDATE")
    test_validate_sql_rejects_delete()
    print("[ok] validate_sql rechaza DELETE")
    test_validate_sql_rejects_drop()
    print("[ok] validate_sql rechaza DROP")
    test_validate_sql_rejects_into_outfile()
    print("[ok] validate_sql rechaza INTO OUTFILE")
    test_validate_sql_rejects_load_file()
    print("[ok] validate_sql rechaza LOAD_FILE")
    test_validate_sql_rejects_multi_statement()
    print("[ok] validate_sql rechaza multi-statement")
    test_validate_sql_accepts_select()
    print("[ok] validate_sql acepta SELECT")
    test_validate_sql_accepts_show()
    print("[ok] validate_sql acepta SHOW")
    test_validate_sql_accepts_describe()
    print("[ok] validate_sql acepta DESCRIBE")
    test_validate_sql_accepts_explain()
    print("[ok] validate_sql acepta EXPLAIN")
    test_validate_sql_trailing_semicolon()
    print("[ok] validate_sql acepta trailing ;")
    test_handle_unknown_operation()
    print("[ok] handle operation desconocido")
    test_handle_empty_sql()
    print("[ok] handle SQL vacío")
    test_handle_policy_violation()
    print("[ok] handle violación policy")
    print("\n=== Todos los tests pasaron ===")
