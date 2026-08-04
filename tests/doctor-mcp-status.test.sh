#!/usr/bin/env bash
# P0: Doctor MCP status classification — tests check_mcp_live patterns
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

source "$ROOT_DIR/scripts/lib/mcp-health.sh"

PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

printf '=== Doctor MCP status classification ===\n'
check() {
  local name=$1 output=$2 expected=$3
  local actual
  actual=$(classify_mcp_debug_output "$output")
  if [[ "$actual" == "$expected" ]]; then
    pass "status $name (got: $actual)"
  else
    fail "status $name (expected: $expected, got: $actual)"
  fi
}

check "connected" "connected" "connected"
check "healthy" "healthy" "connected"
check "not-connected" "not connected" "inaccesible"
check "auth-required" "authentication required" "auth-required"
check "auth-failed" "authentication failed" "auth-required"
check "401" "401 Unauthorized" "auth-required"
check "missing-creds" "missing credentials" "auth-required"
check "broken-pipe" "broken pipe" "inaccesible"
check "conn-refused" "connection refused" "inaccesible"
check "empty" "" "desconocido"
check "opencode-error" "error: something bad" "inaccesible"
check "not-found" "not found" "inaccesible"

# --- --skip-oauth behavior via real doctor.sh with custom HOME ---
printf '\n=== Doctor --skip-oauth tests ===\n'
STUBS="$TMP_DIR/stubs"
HOME_DIR="$TMP_DIR/home"
mkdir -p "$STUBS" "$HOME_DIR/.config/daniel-harness/state" "$HOME_DIR/.config/daniel-harness/secrets/tunnels" "$HOME_DIR/.config/opencode"
printf '%s\n' 'version: "1"' 'models:' '  - id: default' '    trust: trusted' '    allowArbitraryShell: false' '    allowedCapabilities: []' > "$HOME_DIR/.config/daniel-harness/config.yaml"

# Stubs that actually work (heredoc to avoid noexec issues)
cat > "$STUBS/sudo" <<'STUB'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
STUB
chmod +x "$STUBS/sudo"

for s in gentle-ai codegraph engram rtk dh gh aws node npm docker; do
  cat > "$STUBS/$s" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUBS/$s"
done

cat > "$STUBS/gentle-ai" <<'STUB'
#!/bin/bash
case "$1" in
  version) echo "gentle-ai 9.9.9 (stub)" ;;
  doctor) echo "Status:  healthy" ;;
  review) echo "receipt-driven development: on" ;;
  skill-registry) ;;
  sync) ;;
esac
exit 0
STUB
chmod +x "$STUBS/gentle-ai"
# opencode stub returns auth-required for all MCPs
cat > "$STUBS/opencode" <<'STUB'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "authentication required"; exit 0; fi
exit 0
STUB
chmod +x "$STUBS/opencode"

cat > "$HOME_DIR/.config/opencode/opencode.json" <<'JSON'
{"$schema":"https://opencode.ai/config.json","plugin":[],"mcp":{"codegraph":{"type":"local","command":["codegraph","serve","--mcp"],"enabled":true},"engram":{"type":"local","command":["engram","mcp","--tools=agent"],"enabled":true},"test-mcp":{"type":"remote","url":"https://example.com/mcp","enabled":true}}}
JSON
mkdir -p "$HOME_DIR/.config/opencode/agents" "$HOME_DIR/.config/opencode/skills" "$HOME_DIR/.config/opencode/commands"
for a in alegra-microservice-engineer code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  touch "$HOME_DIR/.config/opencode/agents/$a.md"
done
for s in monolith-to-micro-migration task-lifecycle; do
  mkdir -p "$HOME_DIR/.config/opencode/skills/$s"
done

# Without --skip-oauth: should be critical
result=$(cd "$ROOT_DIR" && env PATH="$STUBS:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
  bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict 2>&1 || true)
echo "$result" | grep -qE '^\[cr[íi]tico\]' && pass "skip-oauth off: critical reported" || {
  echo "---doctor output (no critical found)---"
  echo "$result" | grep -E '(cr[ií]tico|aviso|mcp)'
  fail "skip-oauth off: no critical"
}

# With --skip-oauth: should NOT have critical
result=$(cd "$ROOT_DIR" && env PATH="$STUBS:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
  bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict --skip-oauth 2>&1 || true)
! echo "$result" | grep -qE '^\[cr[íi]tico\]' && pass "skip-oauth on: no critical" || {
  echo "---doctor output (critical found)---"
  echo "$result" | grep -E '^\[cr[íi]tico\]'
  fail "skip-oauth on: has critical"
}
echo "$result" | grep -q 'aviso' && pass "skip-oauth on: auth is warning" || fail "skip-oauth on: auth not downgraded"

# --- Missing/invalid config tests ---
printf '\n=== Missing/invalid config tests ===\n'
rm -f "$HOME_DIR/.config/opencode/opencode.json"
result=$(cd "$ROOT_DIR" && env PATH="$STUBS:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
  bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict 2>&1 || true)
echo "$result" | grep -qE '^\[cr[íi]tico\]' && pass "strict+profile: missing config is critical" || fail "strict+profile: missing config not critical"

echo 'NOT JSON' > "$HOME_DIR/.config/opencode/opencode.json"
result=$(cd "$ROOT_DIR" && env PATH="$STUBS:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
  bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict 2>&1 || true)
echo "$result" | grep -qE '^\[cr[íi]tico\]' && pass "strict+profile: invalid config is critical" || fail "strict+profile: invalid config not critical"

rm -f "$HOME_DIR/.config/opencode/opencode.json"
result=$(cd "$ROOT_DIR" && env PATH="$STUBS:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
  bash "$ROOT_DIR/scripts/doctor.sh" 2>&1 || true)
echo "$result" | grep -qE '^\[aviso\]' && pass "no-profile: missing config is warning" || fail "no-profile: missing config not warning"
! echo "$result" | grep -qE '^\[cr[íi]tico\]' && pass "no-profile: missing config no critical" || fail "no-profile: missing config has critical"

# --- Summary ---
printf '\n========================================\n'
printf '  Doctor MCP status: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
