#!/usr/bin/env bash
# P0: MCP reconciliation — state, ownership, drift, transiciones, conflictos
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_DIR="$TMP_DIR/home"
STUBS="$TMP_DIR/stubs"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }
run_check() {
  local label=$1; shift
  set +e
  "$@" > "$TMP_DIR/${label// /_}.out" 2>&1; local rc=$?
  set -e
  printf '%s' "$rc"
}

# --- Setup: stubs bootstrap environment ---
printf '=== Setup ===\n'
mkdir -p "$STUBS" "$HOME_DIR/.nvm/versions/node/v24.0.0/bin" "$HOME_DIR/.config/daniel-harness/secrets/tunnels"

cat > "$STUBS/sudo" <<'STUB'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
STUB
chmod +x "$STUBS/sudo"
for stub in apt-get dpkg curl node npm gentle-ai codegraph engram rtk dh; do
  cat > "$STUBS/$stub" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUBS/$stub"
done

cat > "$STUBS/node" <<'STUB'
#!/bin/bash
echo "v24.0.0"
STUB
chmod +x "$STUBS/node"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "$1:${2:-}:${3:-}" in
  --version::) echo "opencode 1.18.18"; exit 0 ;;
  agent:list:--help|mcp:--help:|mcp:debug:--help|mcp:auth:--help|debug:config:--help) exit 0 ;;
esac
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug) echo "connected"; exit 0 ;; esac ;;
esac
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

cat > "$STUBS/gentle-ai" <<'GENTLE'
#!/bin/bash
case "$1" in
  --version) echo "gentle-ai 2.3.0" ;;
  skill-registry|sync) exit 0 ;;
  doctor) echo "Status:  healthy" ;;
esac
GENTLE
chmod +x "$STUBS/gentle-ai"

cat > "$HOME_DIR/.nvm/nvm.sh" <<'NVM'
nvm() { case "$1" in --version) echo "0.40.4" ;; install) ;; alias) ;; *) ;; esac; }
NVM

printf '%s' 'version: "1"
defaultScope: single-repo
models:
  - id: default
    trust: trusted
    allowArbitraryShell: false
    allowedCapabilities: []
' > "$HOME_DIR/.config/daniel-harness/config.yaml"

export PATH="$STUBS:$PATH"

bootstrap() {
  local profile=$1 home=$2
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    GITHUB_PERSONAL_ACCESS_TOKEN="ghp_fixture_not_real" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile "$profile"
}

STATE_FILE="$HOME_DIR/.config/daniel-harness/state/opencode-managed.json"
OC_FILE="$HOME_DIR/.config/opencode/opencode.json"

# --- Test 1: Clean creation ---
printf '\n=== Test 1: Clean creation ===\n'
bootstrap core "$HOME_DIR"
[[ $? -eq 0 ]] && pass "1a: bootstrap core exits 0" || fail "1a: bootstrap core failed"
[[ -f "$OC_FILE" ]] && pass "1b: opencode.json created" || fail "1b: opencode.json missing"
jq -e '.mcp | has("codegraph")' "$OC_FILE" >/dev/null && pass "1c: codegraph in opencode.json" || fail "1c: codegraph missing"
jq -e '.mcp | has("engram")' "$OC_FILE" >/dev/null && pass "1d: engram in opencode.json" || fail "1d: engram missing"
jq -e '.mcp | has("linear") | not' "$OC_FILE" >/dev/null && pass "1e: linear not in core" || fail "1e: linear should not be in core"
jq -e '.mcp.codegraph.type == "local"' "$OC_FILE" >/dev/null && pass "1f: codegraph type local" || fail "1f: codegraph type wrong"
jq -e '.mcp.engram.type == "local"' "$OC_FILE" >/dev/null && pass "1g: engram type local" || fail "1g: engram type wrong"
[[ -f "$STATE_FILE" ]] && pass "1h: state file exists" || fail "1h: state file missing"
STAT_MODE=$(stat -c '%a' "$STATE_FILE" 2>/dev/null || echo "000")
[[ "$STAT_MODE" == "600" ]] && pass "1i: state file mode 600" || fail "1i: state file mode is $STAT_MODE, expected 600"
jq -e '.mcps | has("codegraph")' "$STATE_FILE" >/dev/null && pass "1j: state has codegraph" || fail "1j: state missing codegraph"
jq -e '.mcps | has("engram")' "$STATE_FILE" >/dev/null && pass "1k: state has engram" || fail "1k: state missing engram"
jq -e '.mcps.codegraph.lastAppliedHash | length > 0' "$STATE_FILE" >/dev/null && pass "1l: state has hash for codegraph" || fail "1l: state missing hash for codegraph"
# No _managed in opencode.json
jq -e '[.mcp[] | has("_managed")] | any | not' "$OC_FILE" >/dev/null && pass "1m: no _managed in opencode.json" || fail "1m: _managed leaked to opencode.json"

# --- Test 2: Idempotence ---
printf '\n=== Test 2: Idempotence ===\n'
FIRST_HASH=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
STATE_HASH_BEFORE=$(sha256sum "$STATE_FILE" | cut -d' ' -f1)
BACKUPS_BEFORE=$(find "$HOME_DIR/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
bootstrap core "$HOME_DIR"
SECOND_HASH=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
[[ "$FIRST_HASH" == "$SECOND_HASH" ]] && pass "2a: opencode.json unchanged" || fail "2a: opencode.json changed"
BACKUPS_AFTER=$(find "$HOME_DIR/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
[[ "$BACKUPS_AFTER" -eq "$BACKUPS_BEFORE" ]] && pass "2b: no new backups" || fail "2b: unexpected backups ($BACKUPS_BEFORE → $BACKUPS_AFTER)"

# --- Test 3: Core → alegra transition (ascending) ---
printf '\n=== Test 3: Core → alegra transition ===\n'
bootstrap alegra "$HOME_DIR"
[[ $? -eq 0 ]] && pass "3a: bootstrap alegra exits 0" || fail "3a: bootstrap alegra failed"
for mcp in codegraph engram linear context7 wiki-alegra github; do
  jq -e --arg n "$mcp" '.mcp | has($n)' "$OC_FILE" >/dev/null && pass "3b: $mcp present after transition" || fail "3b: $mcp missing after transition"
done
# GitHub headers preserved
jq -e '.mcp.github.headers.Authorization != null' "$OC_FILE" >/dev/null && pass "3c: github Authorization header" || fail "3c: github missing Authorization"
jq -e '.mcp.github.headers["X-MCP-Toolsets"] != null' "$OC_FILE" >/dev/null && pass "3d: github X-MCP-Toolsets" || fail "3d: github missing X-MCP-Toolsets"
jq -e '.mcp.github.oauth == false' "$OC_FILE" >/dev/null && pass "3e: github oauth false" || fail "3e: github oauth not false"
jq -e '.mcp.linear.oauth == {}' "$OC_FILE" >/dev/null && pass "3f: linear oauth {}" || fail "3f: linear oauth not {}"
# State tracks all 6
for mcp in codegraph engram linear context7 wiki-alegra github; do
  jq -e --arg n "$mcp" '.mcps | has($n)' "$STATE_FILE" >/dev/null && pass "3g: state has $mcp" || fail "3g: state missing $mcp"
done

# --- Test 4: alegra → core → alegra (descending and return) ---
printf '\n=== Test 4: alegra → core → alegra ===\n'
# Capture alegra MCP hashes for drift comparison later
ALEGRA_HASH=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
bootstrap core "$HOME_DIR"
[[ $? -eq 0 ]] && pass "4a: back to core exits 0" || fail "4a: back to core failed"
# verify alegra MCPs still in state
jq -e '.mcps | has("linear")' "$STATE_FILE" >/dev/null && pass "4b: state retains linear ownership" || fail "4b: state lost linear"
jq -e '.mcps | has("github")' "$STATE_FILE" >/dev/null && pass "4c: state retains github ownership" || fail "4c: state lost github"
# Now back to alegra
bootstrap alegra "$HOME_DIR"
[[ $? -eq 0 ]] && pass "4d: return to alegra exits 0" || fail "4d: return to alegra failed"
for mcp in codegraph engram linear context7 wiki-alegra github; do
  jq -e --arg n "$mcp" '.mcp | has($n)' "$OC_FILE" >/dev/null && pass "4e: $mcp restored" || fail "4e: $mcp not restored"
done
jq -e '.mcp.github.headers.Authorization != null' "$OC_FILE" >/dev/null && pass "4f: github Authorization intact" || fail "4f: github Authorization lost"

# --- Test 5: Preexisting custom MCP (no state) ---
printf '\n=== Test 5: Preexisting custom MCP ===\n'
CUSTOM_HOME="$TMP_DIR/home-custom"
mkdir -p "$CUSTOM_HOME/.config/opencode"
mkdir -p "$CUSTOM_HOME/.nvm/versions/node/v24.0.0/bin" "$CUSTOM_HOME/.config/daniel-harness/secrets/tunnels"
echo '#!/bin/bash; echo v24.0.0' > "$CUSTOM_HOME/.nvm/versions/node/v24.0.0/bin/node"
chmod +x "$CUSTOM_HOME/.nvm/versions/node/v24.0.0/bin/node"
echo 'nvm() { :; }' > "$CUSTOM_HOME/.nvm/nvm.sh"
printf '%s\n' 'version: "1"' 'models:' '  - id: default' '    trust: trusted' '    allowArbitraryShell: false' '    allowedCapabilities: []' > "$CUSTOM_HOME/.config/daniel-harness/config.yaml"

# Create opencode.json with a custom github MCP (different URL than manifest)
jq -n '{
  "plugin": [],
  "mcp": {
    "github": {
      "type": "remote",
      "url": "https://custom.example/mcp",
      "enabled": true
    }
  }
}' > "$CUSTOM_HOME/.config/opencode/opencode.json"

# Bootstrap alegra (github is in alegra profile, but no state file)
env PATH="$STUBS:$PATH" HOME="$CUSTOM_HOME" XDG_CONFIG_HOME="$CUSTOM_HOME/.config" NVM_DIR="$CUSTOM_HOME/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/custom-bootstrap.out" 2>&1 || true
# Custom github should NOT be overwritten (different URL than manifest, no state)
CUSTOM_URL=$(jq -r '.mcp.github.url // "missing"' "$CUSTOM_HOME/.config/opencode/opencode.json" 2>/dev/null || echo "missing")
[[ "$CUSTOM_URL" == "https://custom.example/mcp" ]] && pass "5a: custom github preserved" || fail "5a: custom github was overwritten ($CUSTOM_URL)"
# Warning should have been emitted
grep -q 'personalizado' "$TMP_DIR/custom-bootstrap.out" && pass "5b: warning about custom MCP" || {
  cat "$TMP_DIR/custom-bootstrap.out" | head -30
  fail "5b: no warning for custom MCP"
}

# --- Test 6: User drift detection ---
printf '\n=== Test 6: User drift detection ===\n'
DRIFT_HOME="$TMP_DIR/home-drift"
mkdir -p "$DRIFT_HOME/.nvm/versions/node/v24.0.0/bin" "$DRIFT_HOME/.config/daniel-harness/secrets/tunnels"
echo '#!/bin/bash; echo v24.0.0' > "$DRIFT_HOME/.nvm/versions/node/v24.0.0/bin/node"
chmod +x "$DRIFT_HOME/.nvm/versions/node/v24.0.0/bin/node"
echo 'nvm() { :; }' > "$DRIFT_HOME/.nvm/nvm.sh"
printf '%s\n' 'version: "1"' 'models:' '  - id: default' '    trust: trusted' '    allowArbitraryShell: false' '    allowedCapabilities: []' > "$DRIFT_HOME/.config/daniel-harness/config.yaml"

# Bootstrap core → alegra (establish state with hashes)
env PATH="$STUBS:$PATH" HOME="$DRIFT_HOME" XDG_CONFIG_HOME="$DRIFT_HOME/.config" NVM_DIR="$DRIFT_HOME/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > /dev/null 2>&1

# Now modify github URL manually
jq '.mcp.github.url = "https://evil.example/mcp"' "$DRIFT_HOME/.config/opencode/opencode.json" > "$TMP_DIR/evil.json" && mv "$TMP_DIR/evil.json" "$DRIFT_HOME/.config/opencode/opencode.json"

# Second bootstrap should detect drift
env PATH="$STUBS:$PATH" HOME="$DRIFT_HOME" XDG_CONFIG_HOME="$DRIFT_HOME/.config" NVM_DIR="$DRIFT_HOME/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/drift-bootstrap.out" 2>&1 || true
# GitHub should still be custom URL (not overwritten)
DRIFT_URL=$(jq -r '.mcp.github.url // "missing"' "$DRIFT_HOME/.config/opencode/opencode.json" 2>/dev/null || echo "missing")
[[ "$DRIFT_URL" == "https://evil.example/mcp" ]] && pass "6a: drifted github preserved" || fail "6a: drifted github was reset ($DRIFT_URL)"
grep -q 'modificado externamente' "$TMP_DIR/drift-bootstrap.out" && pass "6b: drift detection warning" || {
  cat "$TMP_DIR/drift-bootstrap.out"
  fail "6b: no drift warning"
}

# --force does not exist yet, but test that normal mode respects drift

# --- Test 7: State file write failure ---
printf '\n=== Test 7: State file write failure ===\n'
STATE_FAIL_HOME="$TMP_DIR/home-statefail"
mkdir -p "$STATE_FAIL_HOME/.nvm/versions/node/v24.0.0/bin" "$STATE_FAIL_HOME/.config/daniel-harness/secrets/tunnels"
echo '#!/bin/bash; echo v24.0.0' > "$STATE_FAIL_HOME/.nvm/versions/node/v24.0.0/bin/node"
chmod +x "$STATE_FAIL_HOME/.nvm/versions/node/v24.0.0/bin/node"
echo 'nvm() { :; }' > "$STATE_FAIL_HOME/.nvm/nvm.sh"
printf '%s\n' 'version: "1"' 'models:' '  - id: default' '    trust: trusted' '    allowArbitraryShell: false' '    allowedCapabilities: []' > "$STATE_FAIL_HOME/.config/daniel-harness/config.yaml"

# Make state dir unwritable (lock file can't be created)
mkdir -p "$STATE_FAIL_HOME/.config/daniel-harness/state"
chmod 000 "$STATE_FAIL_HOME/.config/daniel-harness/state"

# Bootstrap must fail closed when lock cannot be created
set +e
env PATH="$STUBS:$PATH" HOME="$STATE_FAIL_HOME" XDG_CONFIG_HOME="$STATE_FAIL_HOME/.config" NVM_DIR="$STATE_FAIL_HOME/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/statefail.out" 2>&1
RC=$?
set -e
[[ $RC -ne 0 ]] && pass "7a: bootstrap fails when state unwritable (exit $RC)" || fail "7a: bootstrap should fail when state unwritable"

chmod 755 "$STATE_FAIL_HOME/.config/daniel-harness/state" 2>/dev/null || true

# --- Summary ---
printf '\n========================================\n'
printf '  MCP Reconciliation: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
