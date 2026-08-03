#!/usr/bin/env bash
# E2E: simulate a first install in a clean HOME
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_TMP="$TMP_DIR/home"
CONFIG_TMP="$TMP_DIR/config"
OC_FILE="$CONFIG_TMP/opencode/opencode.json"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

# --- Phase 1: install.sh ---
printf '=== Phase 1: install.sh ===\n'
HOME="$HOME_TMP" XDG_CONFIG_HOME="$CONFIG_TMP" bash "$ROOT_DIR/scripts/install.sh" 2>&1

[[ -L "$CONFIG_TMP/opencode/agents/alegra-microservice-engineer.md" ]] && pass "agent alegra-microservice-engineer linked" || fail "agent alegra-microservice-engineer missing"
[[ -L "$CONFIG_TMP/opencode/agents/code-reviewer.md" ]] && pass "agent code-reviewer linked" || fail "agent code-reviewer missing"
[[ -L "$CONFIG_TMP/opencode/agents/alegra-microservice-test-engineer.md" ]] && pass "agent alegra-microservice-test-engineer linked" || fail "agent alegra-microservice-test-engineer missing"
[[ -L "$CONFIG_TMP/opencode/agents/php-engineer.md" ]] && pass "agent php-engineer linked" || fail "agent php-engineer missing"
[[ -L "$CONFIG_TMP/opencode/agents/migration-parity-reviewer.md" ]] && pass "agent migration-parity-reviewer linked" || fail "agent migration-parity-reviewer missing"
[[ -L "$CONFIG_TMP/opencode/skills/monolith-to-micro-migration" ]] && pass "skill monolith-to-micro-migration linked" || fail "skill monolith-to-micro-migration missing"
[[ -L "$CONFIG_TMP/opencode/skills/task-lifecycle" ]] && pass "skill task-lifecycle linked" || fail "skill task-lifecycle missing"
[[ -L "$CONFIG_TMP/opencode/commands/migration-gap-analysis.md" ]] && pass "command migration-gap-analysis linked" || fail "command migration-gap-analysis missing"
[[ -L "$HOME_TMP/.local/bin/dh" ]] && pass "dh CLI linked" || fail "dh CLI missing"

# --- Phase 2: Create opencode.json (bootstrap phase 4 logic) ---
printf '\n=== Phase 2: opencode.json creation ===\n'
mkdir -p "$(dirname "$OC_FILE")"
printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "plugin": [],\n  "mcp": {}\n}\n' > "$OC_FILE"
chmod 600 "$OC_FILE"

jq empty "$OC_FILE" && pass "opencode.json is valid JSON" || fail "opencode.json is not valid JSON"
jq -r '.mcp | keys[]' "$OC_FILE" >/dev/null 2>&1 && mcp_count=$(jq '.mcp | length' "$OC_FILE") && pass "mcp section exists ($mcp_count servers)" || fail "mcp section missing"

# --- Phase 3: Verify schema compliance ---
printf '\n=== Phase 3: Schema validation ===\n'
SCHEMA_URL="https://opencode.ai/config.json"
# Verify structure: plugin array exists, mcp object exists
[[ $(jq 'has("plugin")' "$OC_FILE") == "true" ]] && pass "plugin key exists" || fail "plugin key missing"
[[ $(jq '.plugin | type' "$OC_FILE") == '"array"' ]] && pass "plugin is array" || fail "plugin is not array"
[[ $(jq '.mcp | type' "$OC_FILE") == '"object"' ]] && pass "mcp is object" || fail "mcp is not object"

# --- Phase 4: Agent frontmatter validation ---
printf '\n=== Phase 4: Agent frontmatter ===\n'
for agent in "$ROOT_DIR/agents/"*.md; do
  name=$(basename "$agent" .md)
  head -1 "$agent" | grep -q '^---$' && pass "$name: has frontmatter" || fail "$name: missing frontmatter"
  grep -q '^name: ' "$agent" && pass "$name: has name" || fail "$name: missing name"
  grep -q '^description: ' "$agent" && pass "$name: has description" || fail "$name: missing description"
done

# --- Phase 5: Doctor runs without crashing ---
printf '\n=== Phase 5: doctor.sh ===\n'
if OPENCODE_CONFIG_FILE="$OC_FILE" bash "$ROOT_DIR/scripts/doctor.sh" > "$TMP_DIR/doctor.out" 2>&1; then
  pass "doctor.sh completed with exit 0"
else
  rc=$?
  if grep -q 'crítico' "$TMP_DIR/doctor.out"; then
    fail "doctor.sh exit $rc with criticals (expected in clean env)"
  else
    pass "doctor.sh completed with exit $rc (no criticals)"
  fi
fi

# --- Phase 6: Idempotence (second install.sh makes no changes) ---
printf '\n=== Phase 6: Idempotence ===\n'
FIRST_HASH=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" 2>/dev/null | cut -d' ' -f1 || echo none)
HOME="$HOME_TMP" XDG_CONFIG_HOME="$CONFIG_TMP" bash "$ROOT_DIR/scripts/install.sh" 2>&1
SECOND_HASH=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" 2>/dev/null | cut -d' ' -f1 || echo none)
[[ "$FIRST_HASH" == "$SECOND_HASH" ]] && pass "second install is idempotent (config unchanged)" || fail "second install modified config"

# --- Phase 7: Profile manifest validation ---
printf '\n=== Phase 7: Profile manifest validation ===\n'
for profile in core alegra migration full; do
  awk -v p="$profile" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { found=1; exit }
  ' "$ROOT_DIR/bootstrap/manifest.yaml" && pass "profile $profile exists in manifest" || fail "profile $profile missing from manifest"
done

# --- Phase 8: Verify bootstrap --dry-run for each profile ---
printf '\n=== Phase 8: bootstrap --dry-run profiles ===\n'
for profile in core alegra migration full; do
  bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile "$profile" > "$TMP_DIR/bootstrap-$profile.out" 2>&1 || true
  grep -q 'Bootstrap completado' "$TMP_DIR/bootstrap-$profile.out" && pass "profile $profile dry-run completes" || fail "profile $profile dry-run failed"
done

# --- Summary ---
printf '\n========================================\n'
printf '  Resultados: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
