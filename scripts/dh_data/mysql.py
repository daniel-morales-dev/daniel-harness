"""Read-only MySQL/MariaDB query backend with sqlglot parser."""
import json, subprocess, re, os, tempfile
from dh_data.redaction import redact, truncate

ALLOWED_COMMANDS = {'SELECT', 'SHOW', 'DESCRIBE', 'DESC', 'EXPLAIN'}
BLOCKED_KEYWORDS = [
    'INTO OUTFILE', 'INTO DUMPFILE', 'LOAD_FILE',
    'FOR UPDATE', 'FOR SHARE', 'LOCK IN SHARE MODE',
    'SLEEP', 'BENCHMARK',
]

def validate_sql(sql):
    import sqlglot
    stripped = sql.strip().rstrip(';')
    if not stripped:
        raise ValueError("empty SQL query")

    try:
        parsed = sqlglot.parse(stripped, dialect="mysql", error_level=sqlglot.ErrorLevel.RAISE)
    except Exception as e:
        raise ValueError(f"invalid SQL: {e}")

    if not parsed or len(parsed) == 0:
        raise ValueError("empty or unparseable SQL")
    if len(parsed) > 1:
        raise ValueError("multi-statement not allowed")

    statement = parsed[0]
    if statement is None:
        raise ValueError("empty or unparseable SQL")

    node_type = type(statement).__name__.upper()
    if node_type == 'SELECT':
        first = 'SELECT'
    elif node_type == 'SHOW':
        first = 'SHOW'
    elif node_type in ('DESCRIBE', 'EXPLAIN'):
        first = node_type
    else:
        actual = re.sub(r'(Statement)$', '', node_type).upper()
        raise ValueError(f"only SELECT/SHOW/DESCRIBE/EXPLAIN allowed, got '{actual}'")

    # Walk all nodes to block dangerous constructs
    for node in statement.walk():
        nn = type(node).__name__.upper()
        if nn in ('DELETE', 'UPDATE', 'INSERT', 'DROP', 'ALTER', 'CREATE', 'TRUNCATE', 'REPLACE', 'CALL', 'MERGE'):
            raise ValueError(f"write/DDL statement not allowed: {nn}")
        if nn == 'FUNCTION' and str(node).upper() in ('SLEEP', 'BENCHMARK', 'LOAD_FILE'):
            raise ValueError(f"blocked function: {node}")

    # Secondary regex checks
    upper = stripped.upper()
    for kw in BLOCKED_KEYWORDS:
        if kw in upper:
            # SHOW FOR UPDATE is valid in some contexts but not others — block all
            raise ValueError(f"blocked clause: {kw}")

    return stripped

def handle(profile, credentials, operation, params):
    if operation != "query":
        return {"error": f"Operación no soportada: {operation}"}, 2
    sql = params.get("sql", "")
    try:
        sql = validate_sql(sql)
    except ValueError as e:
        return {"error": str(e)}, 2
    conn_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.cnf', delete=False) as f:
            f.write(credentials)
            conn_path = f.name
        os.chmod(conn_path, 0o600)
        host = profile.get('host', '127.0.0.1')
        port = profile.get('port', 3306)
        cmd = ['mysql', f'--defaults-extra-file={conn_path}',
               '-h', str(host), '-P', str(port), '--batch', '--raw', '-e', sql]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return {"error": redact(result.stderr.strip())}, 1
        lines = result.stdout.strip().split('\n')
        if not lines or not lines[0]:
            return {"rows": []}, 0
        headers = lines[0].split('\t')
        rows = []
        for line in lines[1:]:
            if not line.strip():
                continue
            vals = line.split('\t')
            rows.append({h: vals[i] if i < len(vals) else None for i, h in enumerate(headers)})
        rows, truncated = truncate(rows, max_records=1000)
        rows = [{k: redact(str(v)) if isinstance(v, str) else v for k, v in r.items()} for r in rows]
        return {"rows": rows, "truncated": truncated}, 0
    except subprocess.TimeoutExpired:
        return {"error": "Query timed out after 30s"}, 1
    except FileNotFoundError:
        return {"error": "mysql client not found"}, 1
    finally:
        if conn_path and os.path.exists(conn_path):
            os.unlink(conn_path)
