#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE="$TMP_DIR/opencode.json"
INVALID="$TMP_DIR/invalid.json"
OUTPUT="$TMP_DIR/redacted.json"

printf '%s\n' '{
  "model": "provider/model",
  "agent": {"build": {"mode": "primary"}},
  "mcp": {
    "github": {
      "type": "remote",
      "enabled": true,
      "url": "https://example.invalid/mcp",
      "headers": {"Authorization": "Bearer synthetic-secret"}
    },
    "local": {
      "type": "local",
      "enabled": false,
      "command": ["synthetic-command", "serve", "--auth-token", "literal-secret-value"],
      "environment": {"API_KEY": "synthetic-key"}
    },
    "safe": {
      "type": "local",
      "command": ["synthetic-command", "serve"]
    }
  },
  "token": "synthetic-token",
  "authToken": "synthetic-compound-token",
  "security": "preserved",
  "tokenizer": "preserved",
  "headersTimeout": 1000,
  "nested": {"Password": "synthetic-password"},
  "permission": {"read": "deny", "bash": "ask"}
}' >"$FIXTURE"
printf '{invalid\n' >"$INVALID"

BEFORE=$(sha256sum "$FIXTURE" | cut -d' ' -f1)
"$ROOT_DIR/scripts/redact-opencode-config.sh" "$FIXTURE" >"$OUTPUT"
AFTER=$(sha256sum "$FIXTURE" | cut -d' ' -f1)

[[ $BEFORE == "$AFTER" ]]
jq -e '.model == "provider/model"' "$OUTPUT" >/dev/null
jq -e '.mcp.github.enabled == true' "$OUTPUT" >/dev/null
jq -e '.mcp.local.command == "<redacted>"' "$OUTPUT" >/dev/null
jq -e '.mcp.safe.command == ["synthetic-command", "serve"]' "$OUTPUT" >/dev/null
jq -e '.mcp.github.url == "<redacted>"' "$OUTPUT" >/dev/null
jq -e '.mcp.github.headers == "<redacted>"' "$OUTPUT" >/dev/null
jq -e '.mcp.local.environment == "<redacted>"' "$OUTPUT" >/dev/null
jq -e '.token == "<redacted>"' "$OUTPUT" >/dev/null
jq -e '.authToken == "<redacted>"' "$OUTPUT" >/dev/null
jq -e '.security == "preserved"' "$OUTPUT" >/dev/null
jq -e '.tokenizer == "preserved"' "$OUTPUT" >/dev/null
jq -e '.headersTimeout == 1000' "$OUTPUT" >/dev/null
jq -e '.nested.Password == "<redacted>"' "$OUTPUT" >/dev/null

if "$ROOT_DIR/scripts/redact-opencode-config.sh" "$INVALID" >"$TMP_DIR/invalid-output" 2>/dev/null; then
  printf 'Expected invalid JSON to fail\n' >&2
  exit 1
fi

[[ ! -s "$TMP_DIR/invalid-output" ]]
printf 'redact-opencode-config tests passed\n'
