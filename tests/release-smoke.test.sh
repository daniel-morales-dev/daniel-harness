#!/usr/bin/env bash
# tests/release-smoke.test.sh
# Smoke test de release v0.1.0 — ejecutar en Ubuntu 24.04 limpio o contenedor equivalente
# Uso:
#   bash tests/release-smoke.test.sh              # REAL environment (Ubuntu 24.04)
#   bash tests/release-smoke.test.sh --stubs       # CI verification with dry-run
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
USE_STUBS=false

for arg in "$@"; do
  [[ "$arg" == "--stubs" ]] && USE_STUBS=true
done

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

HOME_DIR="$TMP_DIR/home"
mkdir -p "$HOME_DIR/.local/bin"
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export NVM_DIR="$HOME_DIR/.nvm"
export DANIEL_HARNESS_CONFIG_DIR="$HOME_DIR/.config/daniel-harness"
export DANIEL_HARNESS_BIN_DIR="$HOME_DIR/.local/bin"
export OPENCODE_CONFIG_DIR="$HOME_DIR/.config/opencode"
export PATH="$HOME_DIR/.local/bin:$PATH"
export NAVI_MCP_URL="https://navi.example.com/mcp"
export NAVI_OAUTH_CLIENT_ID="dummy-client-id"

if $USE_STUBS; then
  DRY="--dry-run"
  mkdir -p "$DANIEL_HARNESS_CONFIG_DIR/secrets/tunnels"
  python3 -c "
import yaml
from pathlib import Path
cfg = yaml.safe_load((Path('$ROOT_DIR/examples/config.example.yaml')).read_text())
cfg['models'] = [m for m in cfg['models'] if m.get('trust') != 'restricted']
Path('$DANIEL_HARNESS_CONFIG_DIR/config.yaml').write_text(yaml.dump(cfg))
" 2>/dev/null || true
else
  DRY=""
fi

echo "=== Smoke Test: v0.1.0 Release ==="

# Step 1: Install core profile
echo "--- Step 1: install core ---"
bash "$ROOT_DIR/scripts/install.sh" > "$TMP_DIR/s1.out" 2>&1 && pass "install core OK" || fail "install core failed"
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core $DRY > "$TMP_DIR/s1b.out" 2>&1
if grep -q 'Bootstrap completado' "$TMP_DIR/s1b.out"; then
  pass "bootstrap core OK"
else
  cat "$TMP_DIR/s1b.out"
  fail "bootstrap core failed"
fi

# Step 2: Doctor --profile core (with --skip-oauth)
echo "--- Step 2: doctor core ---"
bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict --skip-oauth > "$TMP_DIR/s2.out" 2>&1 || true
if grep -q 'Resumen: 0 crítico(s)' "$TMP_DIR/s2.out"; then
  pass "doctor core strict passed"
else
  grep -E '(crítico|Resumen)' "$TMP_DIR/s2.out"
  # In stub mode, doctor may fail because real tools aren't installed
  $USE_STUBS && pass "doctor core: stubs mode (skipped)" || fail "doctor core strict failed"
fi

# Step 3: Second core bootstrap (idempotence)
echo "--- Step 3: core idempotence ---"
OC_HASH_BEFORE=$(sha256sum "$HOME_DIR/.config/opencode/opencode.json" 2>/dev/null | cut -d' ' -f1 || echo "none")
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core $DRY > "$TMP_DIR/s3.out" 2>&1
if grep -q 'Bootstrap completado' "$TMP_DIR/s3.out"; then
  pass "second core OK"
else
  fail "second core failed"
fi
if [[ "$OC_HASH_BEFORE" != "none" ]]; then
  OC_HASH_AFTER=$(sha256sum "$HOME_DIR/.config/opencode/opencode.json" 2>/dev/null | cut -d' ' -f1)
  [[ "$OC_HASH_BEFORE" == "$OC_HASH_AFTER" ]] && pass "core idempotent" || fail "core modified opencode.json"
fi

# Step 4: Alegra profile
echo "--- Step 4: alegra ---"
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra $DRY > "$TMP_DIR/s4.out" 2>&1
grep -q 'Bootstrap completado' "$TMP_DIR/s4.out" && pass "bootstrap alegra OK" || fail "bootstrap alegra failed"

# Step 5: Migration profile (skip docker)
echo "--- Step 5: migration ---"
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile migration --skip-docker $DRY > "$TMP_DIR/s5.out" 2>&1
grep -q 'Bootstrap completado' "$TMP_DIR/s5.out" && pass "bootstrap migration OK" || fail "bootstrap migration failed"

# Step 6: Full profile
echo "--- Step 6: full ---"
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile full $DRY > "$TMP_DIR/s6.out" 2>&1
grep -q 'Bootstrap completado' "$TMP_DIR/s6.out" && pass "bootstrap full OK" || fail "bootstrap full failed"

# Step 7: Schema validation
echo "--- Step 7: schema validation ---"
OC_FILE="$HOME_DIR/.config/opencode/opencode.json"
if [[ -f "$OC_FILE" ]]; then
  SCHEMA_FILE="$ROOT_DIR/tests/fixtures/opencode-config.schema.json"
  if [[ -f "$SCHEMA_FILE" ]]; then
    python3 "$ROOT_DIR/scripts/validate-opencode-config.py" --config "$OC_FILE" --schema "$SCHEMA_FILE" && pass "schema valid" || fail "schema invalid"
  fi
  jq empty "$OC_FILE" && pass "JSON valid" || fail "JSON invalid"
fi

# Step 8: Profile transitions
echo "--- Step 8: profile transitions ---"
for transition in "core" "alegra" "core" "alegra"; do
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile "$transition" $DRY > "$TMP_DIR/s8_${transition}.out" 2>&1
  grep -q 'Bootstrap completado' "$TMP_DIR/s8_${transition}.out" && pass "transition: $transition" || fail "transition: $transition"
done

# Step 9: Content verification
echo "--- Step 9: content verification ---"
AGENT_DIR="$HOME_DIR/.config/opencode/agents"
SKILL_DIR="$HOME_DIR/.config/opencode/skills"
CMD_DIR="$HOME_DIR/.config/opencode/commands"
for agent in alegra-microservice-engineer code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  [[ -f "$AGENT_DIR/$agent.md" || -L "$AGENT_DIR/$agent.md" ]] && pass "agent $agent" || fail "agent $agent missing"
done
for skill in monolith-to-micro-migration task-lifecycle; do
  [[ -d "$SKILL_DIR/$skill" || -L "$SKILL_DIR/$skill" ]] && pass "skill $skill" || fail "skill $skill missing"
done
[[ -f "$CMD_DIR/migration-gap-analysis.md" || -L "$CMD_DIR/migration-gap-analysis.md" ]] && pass "command migration-gap-analysis" || fail "command migration-gap-analysis missing"
# Data tools must NOT be installed by default
for dt in agents/data-access.md commands/mysql-query.md commands/mongodb-query.md commands/dynamodb-read.md commands/dynamodb-write-confirmed.md commands/object-storage-read.md; do
  [[ -e "$HOME_DIR/.config/opencode/$dt" || -L "$HOME_DIR/.config/opencode/$dt" ]] && fail "data tool installed: $dt" || pass "data tool absent: $dt"
done
[[ -f "$HOME_DIR/.local/bin/dh-data-executor" ]] && fail "dh-data-executor installed" || pass "dh-data-executor absent"

# MCPs for alegra profile
if [[ -f "$OC_FILE" ]]; then
  for mcp in codegraph engram linear context7 wiki-alegra github; do
    jq -e ".mcp | has(\"$mcp\")" "$OC_FILE" >/dev/null && pass "MCP $mcp" || fail "MCP $mcp missing"
  done
fi

# Step 10: Permissions
echo "--- Step 10: permissions ---"
STATE_FILE="$DANIEL_HARNESS_CONFIG_DIR/state/opencode-managed.json"
if [[ -f "$STATE_FILE" ]]; then
  [[ $(stat -c '%a' "$STATE_FILE" 2>/dev/null) == "600" ]] && pass "state file mode 600" || fail "state file mode not 600"
fi
if [[ -f "$OC_FILE" ]]; then
  [[ $(stat -c '%a' "$OC_FILE" 2>/dev/null) == "600" ]] && pass "opencode.json mode 600" || fail "opencode.json mode not 600"
fi

echo ""
echo "=== Smoke Test Results: $PASS pass, $FAIL fail ==="
(( FAIL == 0 ))
