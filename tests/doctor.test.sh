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
install -m 600 "$ROOT_DIR/examples/config.example.yaml" "$CONFIG_DIR/config.yaml"
install -m 600 "$ROOT_DIR/examples/connections.example.yaml" "$CONFIG_DIR/connections.yaml"
install -m 600 "$ROOT_DIR/examples/project-registry.example.yaml" "$CONFIG_DIR/project-registry.yaml"

printf '%s\n' '{
  "permission": {"bash": "ask"},
  "security": "preserved",
  "tokenizer": "preserved",
  "headersTimeout": 1000,
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

grep -F '[mcp] name=synthetic-local enabled=true type=local status=available' "$OUTPUT" >/dev/null
grep -F '[mcp] name=synthetic-remote enabled=false type=remote status=not-probed' "$OUTPUT" >/dev/null
grep -F 'No supported hardcoded-secret patterns detected' "$OUTPUT" >/dev/null
grep -F 'Summary: 0 critical' "$OUTPUT" >/dev/null

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

grep -F '[critical] OpenCode configuration contains hardcoded sensitive values' "$OUTPUT" >/dev/null
if grep -F 'literal-secret-value' "$OUTPUT" >/dev/null; then
  printf 'Doctor exposed a synthetic secret\n' >&2
  exit 1
fi

printf 'doctor tests passed\n'
