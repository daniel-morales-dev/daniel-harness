#!/usr/bin/env python3
"""Data tools executor — invocado por custom tools OpenCode.

Recibe JSON estructurado por stdin, valida contra politica,
ejecuta con credenciales internas, devuelve JSON sanitizado.

Exit codes: 0=ok, 1=runtime error, 2=policy violation,
            3=confirmation required, 4=confirmation invalid
"""
import json, sys, os, yaml
from pathlib import Path

HARNESS_DIR = Path(os.environ.get("DANIEL_HARNESS_CONFIG_DIR", "~/.config/daniel-harness")).expanduser()

def load_connections():
    with open(HARNESS_DIR / "connections.yaml") as f:
        return yaml.safe_load(f)

def find_profile(connections, profile_id):
    for p in connections.get("profiles", []):
        if p.get("id") == profile_id:
            return p
    return None

def main():
    raw = sys.stdin.read()
    try:
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON: {e}"}))
        sys.exit(1)

    tool = request.get("tool", "")
    profile_id = request.get("profile", "")
    operation = request.get("operation", "")
    params = request.get("params", {})

    if not tool or not profile_id:
        print(json.dumps({"error": "tool and profile required"}))
        sys.exit(2)

    connections = load_connections()
    profile = find_profile(connections, profile_id)
    if not profile:
        print(json.dumps({"error": f"Profile '{profile_id}' not found"}))
        sys.exit(1)

    ptype = profile.get("type", "")
    read_only = profile.get("readOnly", False)
    write_conf = profile.get("writeConfirmation", {})

    cred_ref = profile.get("credentialsRef", "")

    from dh_data.security import resolve_credentials
    _cred = resolve_credentials(cred_ref, HARNESS_DIR)
    credentials = _cred.get("value") or _cred.get("profile") or ""

    if tool == "mysql-query":
        from dh_data.mysql import handle
    elif tool == "mongodb-query":
        from dh_data.mongodb import handle
    elif tool.startswith("dynamodb-read"):
        from dh_data.dynamodb import handle_read as handle
    elif tool == "dynamodb-write":
        from dh_data.dynamodb import handle_write as handle
    elif tool == "object-storage-read":
        from dh_data.object_storage import handle
    else:
        print(json.dumps({"error": f"Unknown tool: {tool}"}))
        sys.exit(2)

    result, code = handle(profile, credentials, operation, params)
    print(json.dumps(result))
    sys.exit(code)

if __name__ == "__main__":
    main()
