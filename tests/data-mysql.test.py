"""Tests for dh_data/mysql.py — SQL enforcement."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from dh_data.mysql import validate_sql, handle


def test_rejects_insert():
    try:
        validate_sql("INSERT INTO x VALUES (1)")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_update():
    try:
        validate_sql("UPDATE x SET a=1")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_delete():
    try:
        validate_sql("DELETE FROM x")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_drop():
    try:
        validate_sql("DROP TABLE x")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_into_outfile():
    try:
        validate_sql("SELECT * INTO OUTFILE '/tmp/x' FROM t")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_into_dumpfile():
    try:
        validate_sql("SELECT * INTO DUMPFILE '/tmp/x'")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_load_file():
    try:
        validate_sql("SELECT LOAD_FILE('/etc/passwd')")
    except ValueError:
        pass
    else:
        assert False, "should raise"


def test_rejects_multi_statement():
    try:
        validate_sql("SELECT 1; DROP TABLE x")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_for_update():
    try:
        validate_sql("SELECT * FROM users WHERE id = 1 FOR UPDATE")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_sleep():
    try:
        validate_sql("SELECT SLEEP(5)")
        assert False, "should raise"
    except ValueError:
        pass


def test_rejects_benchmark():
    try:
        validate_sql("SELECT BENCHMARK(1000000, MD5('test'))")
        assert False, "should raise"
    except ValueError:
        pass


def test_accepts_select():
    result = validate_sql("SELECT * FROM users WHERE id = 1")
    assert result == "SELECT * FROM users WHERE id = 1"


def test_accepts_show():
    result = validate_sql("SHOW TABLES")
    assert result == "SHOW TABLES"


def test_accepts_describe():
    result = validate_sql("DESCRIBE users")
    assert result == "DESCRIBE users"


def test_accepts_explain():
    result = validate_sql("EXPLAIN SELECT * FROM users")
    assert result == "EXPLAIN SELECT * FROM users"


def test_trailing_semicolon():
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
    test_rejects_insert()
    print("[ok] rejects INSERT")
    test_rejects_update()
    print("[ok] rejects UPDATE")
    test_rejects_delete()
    print("[ok] rejects DELETE")
    test_rejects_drop()
    print("[ok] rejects DROP")
    test_rejects_into_outfile()
    print("[ok] rejects INTO OUTFILE")
    test_rejects_into_dumpfile()
    print("[ok] rejects INTO DUMPFILE")
    test_rejects_load_file()
    print("[ok] rejects LOAD_FILE")
    test_rejects_multi_statement()
    print("[ok] rejects multi-statement")
    test_rejects_for_update()
    print("[ok] rejects FOR UPDATE")
    test_rejects_sleep()
    print("[ok] rejects SLEEP()")
    test_rejects_benchmark()
    print("[ok] rejects BENCHMARK()")
    test_accepts_select()
    print("[ok] accepts SELECT")
    test_accepts_show()
    print("[ok] accepts SHOW")
    test_accepts_describe()
    print("[ok] accepts DESCRIBE")
    test_accepts_explain()
    print("[ok] accepts EXPLAIN")
    test_trailing_semicolon()
    print("[ok] accepts trailing ;")
    test_handle_unknown_operation()
    print("[ok] handle unknown operation")
    test_handle_empty_sql()
    print("[ok] handle empty SQL")
    test_handle_policy_violation()
    print("[ok] handle policy violation")
    print("\n=== Todos los tests pasaron ===")
