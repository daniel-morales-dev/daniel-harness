#!/usr/bin/env bash
# tests/fail-closed.test.sh
# Verifica que bootstrap salga no cero ante fallos de validacion
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
  --version) echo "opencode 1.18.18"; exit 0 ;;
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

OC_FILE="$HOME_DIR/.config/opencode/opencode.json"
STATE_FILE="$HOME_DIR/.config/daniel-harness/state/opencode-managed.json"

_run_and_check() {
  local label=$1; shift
  local cfg_bf st_bf
  cfg_bf=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
  st_bf=$(sha256sum "$STATE_FILE" 2>/dev/null | cut -d' ' -f1 || echo "no-file")
  local out="$TMP_DIR/${label}.out"
  set +e
  "$@" > "$out" 2>&1
  local rc=$?
  set -e
  [[ $rc -ne 0 ]] && pass "$label: exit $rc (expected)" || fail "$label: exit 0 (expected failure)"
  grep -q 'Bootstrap completado' "$out" 2>/dev/null && fail "$label: muestra Bootstrap completado" || pass "$label: no muestra Bootstrap completado"
  local cfg_af st_af
  cfg_af=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
  st_af=$(sha256sum "$STATE_FILE" 2>/dev/null | cut -d' ' -f1 || echo "no-file")
  [[ "$cfg_af" == "$cfg_bf" ]] && pass "$label: config intacto" || fail "$label: config CAMBIO"
  [[ "$st_af" == "$st_bf" ]] && pass "$label: state intacto" || fail "$label: state CAMBIO"
}

# --- Setup ---
echo "=== Setup ==="
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/setup.out" 2>&1 || true
if [[ -f "$OC_FILE" ]]; then
  pass "setup: opencode.json"
else
  cat "$TMP_DIR/setup.out"
  fail "setup: opencode.json missing"
fi
[[ -f "$STATE_FILE" ]] && pass "setup: state" || fail "setup: state missing"

# --- Test 1: Schema invalido ---
echo "=== Test 1: validator forced to fail ==="
echo '{"type": "integer"}' > "$TMP_DIR/broken-schema.json"
rm -f "$STATE_FILE"
jq 'del(.mcp.codegraph)' "$OC_FILE" > "$TMP_DIR/oc-t1.json" && mv "$TMP_DIR/oc-t1.json" "$OC_FILE"
_run_and_check "t1" env DH_OC_SCHEMA="$TMP_DIR/broken-schema.json" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra

# --- Test 2: Candidato JSON invalido ---
echo "=== Test 2: invalid candidate JSON ==="
jq '.mcp.codegraph = {"type":"local","command":["codegraph"],"enabled":true}' "$OC_FILE" > "$TMP_DIR/oc-fixed.json" && mv "$TMP_DIR/oc-fixed.json" "$OC_FILE"
rm -f "$STATE_FILE"
jq 'del(.mcp.codegraph)' "$OC_FILE" > "$TMP_DIR/oc-t2.json" && mv "$TMP_DIR/oc-t2.json" "$OC_FILE"
_run_and_check "t2" env DH_TEST_MODE=1 DH_FAIL_AT=invalid-candidate \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra

# --- Test 3: Coordinador falla antes de publicar ---
echo "=== Test 3: coordinator before apply ==="
# Full baseline restore so state file is valid
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > /dev/null 2>&1
jq 'del(.mcp.codegraph)' "$OC_FILE" > "$TMP_DIR/oc-t3.json" && mv "$TMP_DIR/oc-t3.json" "$OC_FILE"
_run_and_check "t3" env DH_TEST_MODE=1 DH_FAIL_AT=before-apply-opencodeConfig \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra
grep -q 'controlled failpoint: before-apply-opencodeConfig' "$TMP_DIR/t3.out" 2>/dev/null && \
  pass "t3: alcanzó failpoint del coordinador" || \
  fail "t3: no alcanzó failpoint del coordinador"
JOURNAL="$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json"
[[ -f "$JOURNAL" ]] && pass "t3: journal recuperable" || fail "t3: journal ausente"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
