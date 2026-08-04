#!/usr/bin/env bash
# tests/transaction-failures.test.sh
# P1: Verifica que fallos en backup/move/chmod no corrompan config/state
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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

cat > "$STUBS/curl" <<'CURLSCRIPT'
#!/bin/bash
cat <<'NVMSCRIPT'
#!/bin/bash
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
mkdir -p "$NVM_DIR"
cat > "$NVM_DIR/nvm.sh" <<'NVMEOF'
nvm() {
  case "$1" in
    --version) echo "0.40.4" ;;
    install) mkdir -p "$NVM_DIR/versions/node/v24.0.0/bin"
             cat > "$NVM_DIR/versions/node/v24.0.0/bin/node" <<'NODEEOF'
#!/bin/bash
echo "v24.0.0"
NODEEOF
      chmod +x "$NVM_DIR/versions/node/v24.0.0/bin/node" ;;
    alias) ;;
    *) ;;
  esac
}
NVMEOF
chmod +x "$NVM_DIR/nvm.sh"
NVMSCRIPT
CURLSCRIPT
chmod +x "$STUBS/curl"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "connected"; exit 0; fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

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

OC_FILE="$HOME_DIR/.config/opencode/opencode.json"
STATE_FILE="$HOME_DIR/.config/daniel-harness/state/opencode-managed.json"

echo "=== Setup: bootstrap alegra baseline ==="
set +e
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/setup.out" 2>&1
set -e
[[ -f "$OC_FILE" ]] && pass "setup: opencode.json created" || fail "setup: opencode.json missing"
[[ -f "$STATE_FILE" ]] && pass "setup: state file created" || fail "setup: state file missing"

CONFIG_HASH_BEFORE=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
STATE_HASH_BEFORE=$(sha256sum "$STATE_FILE" | cut -d' ' -f1)

echo "=== Test failpoints (else branch: state update, no MCP changes) ==="
# backcup-state: else branch; move-state: else branch; chmod-state: else branch
META_FAILPOINTS=("backup-state" "move-state" "chmod-state")

for fp in "${META_FAILPOINTS[@]}"; do
  set +e
  DH_TEST_MODE=1 DH_FAIL_AT="$fp" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/${fp}.out" 2>&1
  RC=$?
  set -e

  if [[ $RC -ne 0 ]]; then
    pass "${fp}: exit $RC (expected non-zero)"
  else
    fail "${fp}: exit 0 (expected failure)"
  fi

  CONFIG_HASH_NOW=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
  STATE_HASH_NOW=$(sha256sum "$STATE_FILE" | cut -d' ' -f1)

  [[ "$CONFIG_HASH_NOW" == "$CONFIG_HASH_BEFORE" ]] && pass "${fp}: config hash preserved" || fail "${fp}: config hash CHANGED"
  [[ "$STATE_HASH_NOW" == "$STATE_HASH_BEFORE" ]] && pass "${fp}: state hash preserved" || fail "${fp}: state hash CHANGED"

  JOURNAL="$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json"
  [[ ! -f "$JOURNAL" ]] && pass "${fp}: no journal" || fail "${fp}: journal present"
done

echo "=== Test failpoints (add branch: force MCP update) ==="
# Para alcanzar MCP_ADDED>0, limpiamos state y borramos un MCP del config
rm -f "$STATE_FILE"
jq 'del(.mcp.codegraph)' "$OC_FILE" > "$TMP_DIR/oc-reduced.json" && mv "$TMP_DIR/oc-reduced.json" "$OC_FILE"
CONFIG_HASH_ADD=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
STATE_HASH_ADD="no-file"

ADD_FAILPOINTS=("backup-config" "backup-state" "move-config" "move-state" "chmod-state")
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
  [[ ! -f "$JOURNAL" ]] && pass "add-${fp}: no journal" || fail "add-${fp}: journal present"
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

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
