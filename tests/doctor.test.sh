#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_DIR="$TMP_DIR/daniel-harness"
OPENCODE_CONFIG="$TMP_DIR/opencode.json"
OUTPUT="$TMP_DIR/doctor.out"

install -d -m 700 "$CONFIG_DIR"
install -d -m 700 "$CONFIG_DIR/secrets"
install -d -m 700 "$CONFIG_DIR/secrets/tunnels"
install -m 600 "$ROOT_DIR/examples/config.example.yaml" "$CONFIG_DIR/config.yaml"
install -m 600 "$ROOT_DIR/examples/project-registry.example.yaml" "$CONFIG_DIR/project-registry.yaml"

printf '%s\n' 'version: "1"
profiles:
  - id: synthetic-tunnel
    context: freelance
    type: mysql
    environment: testing
    host: 127.0.0.1
    port: 65534
    readOnly: true
    credentialsRef: secrets/mysql/synthetic.cnf
    tunnel:
      required: true
      commandRef: secrets/tunnels/synthetic.command
    writeConfirmation:
      mode: deny' >"$CONFIG_DIR/connections.yaml"
chmod 600 "$CONFIG_DIR/connections.yaml"
printf 'ssh synthetic-host\n' >"$CONFIG_DIR/secrets/tunnels/synthetic.command"
chmod 600 "$CONFIG_DIR/secrets/tunnels/synthetic.command"

printf '%s\n' '{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [],
  "permission": {"bash": "ask"},
  "mcp": {
    "synthetic-local": {
      "type": "local",
      "enabled": true,
      "command": ["sh", "serve"]
    },
    "synthetic-remote": {
      "type": "remote",
      "enabled": false,
      "url": "https://example.invalid/mcp",
      "headers": {"Authorization": "{env:SYNTHETIC_TOKEN}"}
    }
  }
}' >"$OPENCODE_CONFIG"
chmod 600 "$OPENCODE_CONFIG"

if ! DANIEL_HARNESS_CONFIG_DIR="$CONFIG_DIR" \
  OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG" \
  DANIEL_HARNESS_REPO="$ROOT_DIR" \
  "$ROOT_DIR/scripts/doctor.sh" >"$OUTPUT"; then
  printf 'Doctor returned a critical failure:\n' >&2
  while IFS= read -r line; do
    printf '%s\n' "$line" >&2
  done <"$OUTPUT"
  exit 1
fi

grep -F '[mcp] nombre=synthetic-local habilitado=true tipo=local' "$OUTPUT" >/dev/null
grep -F '[mcp] nombre=synthetic-remote habilitado=false tipo=remote estado=deshabilitado' "$OUTPUT" >/dev/null
grep -F 'No se detectaron patrones soportados de secretos hardcodeados' "$OUTPUT" >/dev/null
grep -F 'Falta el túnel synthetic-tunnel (127.0.0.1:65534)' "$OUTPUT" >/dev/null
grep -F "Ejecuta: bash $CONFIG_DIR/secrets/tunnels/synthetic.command" "$OUTPUT" >/dev/null
grep -F 'Resumen: 0 crítico(s)' "$OUTPUT" >/dev/null

if grep -F 'SYNTHETIC_TOKEN' "$OUTPUT" >/dev/null; then
  printf 'Doctor exposed a sensitive reference\n' >&2
  exit 1
fi

printf '%s\n' '{
  "authToken": "literal-secret-value",
  "mcp": {
    "unsafe-local": {
      "type": "local",
      "command": ["synthetic-command", "--api-key=literal-secret-value"]
    }
  }
}' >"$OPENCODE_CONFIG"

if DANIEL_HARNESS_CONFIG_DIR="$CONFIG_DIR" \
  OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG" \
  DANIEL_HARNESS_REPO="$ROOT_DIR" \
  "$ROOT_DIR/scripts/doctor.sh" >"$OUTPUT"; then
  printf 'Expected hardcoded synthetic secrets to fail doctor\n' >&2
  exit 1
fi

grep -F '[crítico] OpenCode contiene valores sensibles hardcodeados' "$OUTPUT" >/dev/null
if grep -F 'literal-secret-value' "$OUTPUT" >/dev/null; then
  printf 'Doctor exposed a synthetic secret\n' >&2
  exit 1
fi

printf '%s\n' '{
  "permission": {"bash": "ask"},
  "url": "https://synthetic-user:synthetic-password@example.invalid/mcp",
  "mcp": {}
}' >"$OPENCODE_CONFIG"

if DANIEL_HARNESS_CONFIG_DIR="$CONFIG_DIR" \
  OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG" \
  DANIEL_HARNESS_REPO="$ROOT_DIR" \
  "$ROOT_DIR/scripts/doctor.sh" >"$OUTPUT"; then
  printf 'Expected embedded synthetic URL credentials to fail doctor\n' >&2
  exit 1
fi

grep -F '[crítico] OpenCode contiene valores sensibles hardcodeados' "$OUTPUT" >/dev/null
if grep -F 'synthetic-password' "$OUTPUT" >/dev/null; then
  printf 'Doctor exposed synthetic URL credentials\n' >&2
  exit 1
fi

# Inject restricted model into config for this test
python3 -c "
import yaml
cfg = yaml.safe_load(open('$CONFIG_DIR/config.yaml'))
if not any(m.get('trust') == 'restricted' for m in cfg.get('models', [])):
  cfg.setdefault('models', []).append({'id': 'test-restricted', 'trust': 'restricted', 'allowArbitraryShell': False, 'allowedCapabilities': ['repository-read-sanitized']})
  yaml.dump(cfg, open('$CONFIG_DIR/config.yaml', 'w'))
"

printf '%s\n' '{"permission":"invalid","mcp":{}}' >"$OPENCODE_CONFIG"

if DANIEL_HARNESS_CONFIG_DIR="$CONFIG_DIR" \
  OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG" \
  DANIEL_HARNESS_REPO="$ROOT_DIR" \
  "$ROOT_DIR/scripts/doctor.sh" >"$OUTPUT"; then
  printf 'Expected an invalid OpenCode permission shape to fail doctor\n' >&2
  exit 1
fi

grep -F '[crítico] No se pudo evaluar el acceso Bash de modelos restricted' "$OUTPUT" >/dev/null

printf 'doctor tests passed\n'
