# scripts/dh_data/mysql.py — Read-only MySQL/MariaDB query backend
import json, subprocess, re, os, tempfile
from dh_data.redaction import redact, truncate

ALLOWED = ('SELECT', 'SHOW', 'DESCRIBE', 'DESC', 'EXPLAIN')
BLOCKED = [
    (re.compile(r'\bINTO\s+OUTFILE\b', re.I), 'INTO OUTFILE'),
    (re.compile(r'\bLOAD_FILE\b', re.I), 'LOAD_FILE'),
]

def validate_sql(sql):
    stripped = sql.strip().rstrip(';')
    if not stripped:
        raise ValueError("Consulta SQL vacía")
    if re.search(r';\s*\S', stripped):
        raise ValueError("Multi-statement no permitido")
    first = stripped.split(None, 1)[0].upper()
    if first not in ALLOWED:
        raise ValueError(f"Solo SELECT/SHOW/DESCRIBE/EXPLAIN permitidos, got '{first}'")
    for pat, name in BLOCKED:
        if pat.search(stripped):
            raise ValueError(f"Operación bloqueada: {name}")
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
        host = profile.get('host', '127.0.0.1')
        port = profile.get('port', 3306)
        cmd = ['mysql', f'--defaults-extra-file={conn_path}',
               '-h', str(host), '-P', str(port), '--batch', '--raw', '-e', sql]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return {"error": result.stderr.strip()}, 1
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
