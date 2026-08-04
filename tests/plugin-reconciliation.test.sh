#!/usr/bin/env bash
# P1: Plugin reconciliation — versión exacta, reemplazo @latest, preservar otros
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

OC_FILE="$TMP_DIR/opencode.json"

# Helper: create opencode.json with given plugins
make_oc() {
  local plugins=$1
  printf '{"$schema":"https://opencode.ai/config.json","plugin":[%s],"mcp":{}}\n' "$plugins" > "$OC_FILE"
}

# Helper: get plugin list
get_plugins() {
  jq -r '.plugin[]' "$OC_FILE" 2>/dev/null | sort | tr '\n' ' '
}

# --- Test 1: No Ponytail — add exact version ---
printf '=== Test 1: Add ponytail when absent ===\n'
make_oc ''
jq --arg p "@dietrichgebert/ponytail@4.8.4" '.plugin = ((.plugin // []) + [$p])' "$OC_FILE" > "${OC_FILE}.tmp" && mv "${OC_FILE}.tmp" "$OC_FILE"
plugins=$(get_plugins)
echo "$plugins" | grep -q '@dietrichgebert/ponytail@4.8.4' && pass "1: ponytail exact version added" || fail "1: ponytail missing"

# --- Test 2: @latest exists — replace by exact ---
printf '\n=== Test 2: Replace @latest ===\n'
make_oc '"@dietrichgebert/ponytail@latest"'
PLUGIN_BASE="@dietrichgebert/ponytail"
PLUGIN_PACKAGE="@dietrichgebert/ponytail@4.8.4"
jq --arg p "$PLUGIN_PACKAGE" --arg b "$PLUGIN_BASE" '.plugin = ((.plugin // []) | map(select(startswith($b) | not)) + [$p])' "$OC_FILE" > "${OC_FILE}.tmp" && mv "${OC_FILE}.tmp" "$OC_FILE"
plugins=$(get_plugins)
echo "$plugins" | grep -q '@dietrichgebert/ponytail@4.8.4' && pass "2a: exact version present" || fail "2a: exact version missing"
echo "$plugins" | grep -q '@latest' && fail "2b: @latest still present" || pass "2b: @latest replaced"

# --- Test 3: Older version exists — replace ---
printf '\n=== Test 3: Replace older version ===\n'
make_oc '"@dietrichgebert/ponytail@4.5.0"'
jq --arg p "$PLUGIN_PACKAGE" --arg b "$PLUGIN_BASE" '.plugin = ((.plugin // []) | map(select(startswith($b) | not)) + [$p])' "$OC_FILE" > "${OC_FILE}.tmp" && mv "${OC_FILE}.tmp" "$OC_FILE"
plugins=$(get_plugins)
echo "$plugins" | grep -q '@dietrichgebert/ponytail@4.8.4' && pass "3a: new version present" || fail "3a: new version missing"
echo "$plugins" | grep -q '@4.5.0' && fail "3b: old version still present" || pass "3b: old version replaced"

# --- Test 4: Other plugins preserved ---
printf '\n=== Test 4: Other plugins preserved ===\n'
make_oc '"other-plugin@1.0.0"'
jq --arg p "$PLUGIN_PACKAGE" --arg b "$PLUGIN_BASE" '.plugin = ((.plugin // []) | map(select(startswith($b) | not)) + [$p])' "$OC_FILE" > "${OC_FILE}.tmp" && mv "${OC_FILE}.tmp" "$OC_FILE"
plugins=$(get_plugins)
echo "$plugins" | grep -q 'other-plugin@1.0.0' && pass "4a: other plugin preserved" || fail "4a: other plugin lost"
echo "$plugins" | grep -q '@dietrichgebert/ponytail@4.8.4' && pass "4b: ponytail also present" || fail "4b: ponytail missing"

# --- Test 5: Second run idempotent ---
printf '\n=== Test 5: Idempotence ===\n'
FIRST=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
jq --arg p "$PLUGIN_PACKAGE" --arg b "$PLUGIN_BASE" '.plugin = ((.plugin // []) | map(select(startswith($b) | not)) + [$p])' "$OC_FILE" > "${OC_FILE}.tmp" && mv "${OC_FILE}.tmp" "$OC_FILE"
SECOND=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
[[ "$FIRST" == "$SECOND" ]] && pass "5: plugin section idempotent" || fail "5: plugin section changed"

# --- Summary ---
printf '\n========================================\n'
printf '  Plugin reconciliation: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
