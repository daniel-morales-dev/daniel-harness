#!/usr/bin/env bash
# tests/transaction-failures.test.sh
# P1: Verifica que fallos en backup/move/chmod no corrompan config/state
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

HOME_DIR="$TMP_DIR/home"
STUBS="$TMP_DIR/stubs"
mkdir -p "$HOME_DIR/.config/daniel-harness/secrets/tunnels" "$HOME_DIR/.nvm" "$STUBS"

for stub in sudo apt-get dpkg curl node npm opencode codegraph rtk engram gentle-ai dh; do
  cat > "$STUBS/$stub" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$STUBS/$stub"
done

cat > "$STUBS/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
EOF
chmod +x "$STUBS/sudo"

create_nvm_curl_stub "$STUBS"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "$1:${2:-}:${3:-}" in
  --version::) echo "opencode 1.18.18"; exit 0 ;;
  agent:list:--help|mcp:--help:|mcp:debug:--help|mcp:auth:--help|debug:config:--help) exit 0 ;;
esac
case "$1" in
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) if [[ "$2" == "debug" ]]; then echo "connected"; exit 0; fi ;;
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

python3 -c "
import yaml
from pathlib import Path
cfg = yaml.safe_load((Path('$ROOT_DIR/examples/config.example.yaml')).read_text())
cfg['models'] = [m for m in cfg['models'] if m.get('trust') != 'restricted']
Path('$HOME_DIR/.config/daniel-harness/config.yaml').write_text(yaml.dump(cfg))
"

export PATH="$STUBS:$PATH"
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export NVM_DIR="$HOME_DIR/.nvm"
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_fixture_not_real"
export DH_TEST_MODE=1
export DH_TRANSACTION_ALLOW_TMP=1

OC_FILE="$HOME_DIR/.config/opencode/opencode.json"
STATE_FILE="$HOME_DIR/.config/daniel-harness/state/opencode-managed.json"

echo "=== Setup: bootstrap alegra baseline ==="
set +e
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/setup.out" 2>&1
set -e
[[ -f "$OC_FILE" ]] && pass "setup: opencode.json created" || fail "setup: opencode.json missing"
[[ -f "$STATE_FILE" ]] && pass "setup: state file created" || fail "setup: state file missing"


echo "=== Test failpoints (add branch: force MCP update) ==="
# Para alcanzar MCP_ADDED>0, limpiamos state y borramos un MCP del config
rm -f "$STATE_FILE"
jq 'del(.mcp.codegraph)' "$OC_FILE" > "$TMP_DIR/oc-reduced.json" && mv "$TMP_DIR/oc-reduced.json" "$OC_FILE"
CONFIG_HASH_ADD=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
STATE_HASH_ADD="no-file"

ADD_FAILPOINTS=("backup-opencodeConfig" "before-apply-opencodeConfig" "after-apply-opencodeConfig")
for fp in "${ADD_FAILPOINTS[@]}"; do
  set +e
  DH_TEST_MODE=1 DH_FAIL_AT="$fp" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/add-${fp}.out" 2>&1
  RC=$?
  set -e

  if [[ $RC -ne 0 ]]; then
    pass "add-${fp}: exit $RC (expected non-zero)"
  else
    fail "add-${fp}: exit 0 (expected failure)"
  fi

  # v0.1.0: TODO los failpoints deben preservar hash exacto de config y state
  CONFIG_HASH_NOW=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
  if [[ -f "$STATE_FILE" ]]; then
    STATE_HASH_NOW=$(sha256sum "$STATE_FILE" | cut -d' ' -f1)
  else
    STATE_HASH_NOW="no-file"
  fi

  [[ "$CONFIG_HASH_NOW" == "$CONFIG_HASH_ADD" ]] && pass "add-${fp}: config hash preserved" || fail "add-${fp}: config hash CHANGED"
  [[ "$STATE_HASH_NOW" == "$STATE_HASH_ADD" ]] && pass "add-${fp}: state hash preserved" || fail "add-${fp}: state hash CHANGED"

  JOURNAL="$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json"
  [[ -f "$JOURNAL" ]] && pass "add-${fp}: recoverable journal" || fail "add-${fp}: journal missing"
done

echo "=== Recovery: bootstrap after all failures ==="
set +e
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/recovery.out" 2>&1
set -e
if [[ -f "$OC_FILE" ]]; then
  pass "recovery: opencode.json exists"
  jq empty "$OC_FILE" && pass "recovery: valid JSON" || fail "recovery: invalid JSON"
  # After all failpoint tests, config should have all alegra MCPs
  for mcp in codegraph engram linear context7 wiki-alegra github; do
    jq -e ".mcp | has(\"$mcp\")" "$OC_FILE" >/dev/null && pass "recovery: MCP $mcp present" || fail "recovery: MCP $mcp missing"
  done
else
  fail "recovery: opencode.json missing"
fi

# Journal debe estar limpio
JOURNAL="$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json"
[[ ! -f "$JOURNAL" ]] && pass "recovery: no journal" || fail "recovery: journal present"

echo "=== Plugin-only reconciliation ==="
# Config con todos los MCPs identicos, Ponytail con version anterior
jq '.plugin = ["@dietrichgebert/ponytail@4.0.0"]' "$OC_FILE" > "$TMP_DIR/oc-old-ponytail.json"
mv "$TMP_DIR/oc-old-ponytail.json" "$OC_FILE"
rm -f "$STATE_FILE"

# Bootstrap debe actualizar Ponytail aunque los MCPs ya existan
set +e
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/plugin-update.out" 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  pass "plugin-only: bootstrap OK"
else
  fail "plugin-only: bootstrap exit $RC"
fi

# Ponytail debe estar actualizado
jq -e '.plugin[] == "@dietrichgebert/ponytail@4.8.4"' "$OC_FILE" >/dev/null && pass "plugin-only: Ponytail updated" || fail "plugin-only: Ponytail NOT updated"

# Segunda ejecucion no debe modificar nada
CONFIG_HASH_AFTER=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
set +e
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/plugin-idempotent.out" 2>&1
RC=$?
set -e
[[ $RC -eq 0 ]] && pass "plugin-only: second bootstrap OK" || fail "plugin-only: second bootstrap exit $RC"
CONFIG_HASH_AFTER2=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
[[ "$CONFIG_HASH_AFTER" == "$CONFIG_HASH_AFTER2" ]] && pass "plugin-only: idempotent" || fail "plugin-only: config changed on second run"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
