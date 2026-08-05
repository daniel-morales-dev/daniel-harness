#!/usr/bin/env bash
# tests/first-run-transaction.test.sh
# Verifica primer arranque transaccional: no crear opencode.json real
# antes de validar el candidato. Rollback respeta existedBeforeConfig.
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

# Verificar estado inicial: no hay archivos
echo "=== Setup: HOME limpio, sin opencode.json ==="
[[ ! -f "$OC_FILE" ]] && pass "clean: opencode.json no existe" || fail "clean: opencode.json existe"
[[ ! -f "$STATE_FILE" ]] && pass "clean: state no existe" || fail "clean: state existe"

# Helper: run bootstrap with failpoint on first-run HOME
_run_first_run() {
  local label=$1
  local env_vars=()
  local arg
  for arg in "${@:2}"; do
    env_vars+=("$arg")
  done
  local out="$TMP_DIR/${label}.out"
  set +e
  env "${env_vars[@]}" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$out" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    pass "$label: exit $rc (expected non-zero en failpoint)"
  else
    fail "$label: exit 0 (expected failure)"
  fi
  # opencode.json NO debe existir (primer arranque, transacción no completada)
  if [[ ! -f "$OC_FILE" ]]; then
    pass "$label: opencode.json no creado"
  else
    fail "$label: opencode.json fue creado (viola transaccional)"
  fi
  # state NO debe existir
  if [[ ! -f "$STATE_FILE" ]]; then
    pass "$label: state no creado"
  else
    fail "$label: state fue creado"
  fi
}

echo "=== Test 1: crash-after-config ==="
_run_first_run "t1" "DH_TEST_MODE=1" "DH_FAIL_AT=crash-after-config"

echo "=== Test 2: move-state ==="
_run_first_run "t2" "DH_TEST_MODE=1" "DH_FAIL_AT=move-state"

echo "=== Test 3: chmod-state ==="
_run_first_run "t3" "DH_TEST_MODE=1" "DH_FAIL_AT=chmod-state"

echo "=== Test 4: crash-after-state ==="
_run_first_run "t4" "DH_TEST_MODE=1" "DH_FAIL_AT=crash-after-state"

echo "=== Recovery: siguiente bootstrap se recupera correctamente ==="
set +e
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/recovery.out" 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  pass "recovery: bootstrap ok"
else
  cat "$TMP_DIR/recovery.out"
  fail "recovery: exit $RC"
fi
[[ -f "$OC_FILE" ]] && pass "recovery: opencode.json creado" || fail "recovery: opencode.json missing"
[[ -f "$STATE_FILE" ]] && pass "recovery: state creado" || fail "recovery: state missing"
jq empty "$OC_FILE" && pass "recovery: opencode.json JSON válido" || fail "recovery: opencode.json inválido"
for mcp in codegraph engram linear context7 wiki-alegra github; do
  jq -e ".mcp | has(\"$mcp\")" "$OC_FILE" >/dev/null && pass "recovery: MCP $mcp presente" || fail "recovery: MCP $mcp missing"
done

echo "=== Test 5: Rollback rm falla (journal conservado) ==="
# Segundo HOME limpio para probar rm fallando en primer arranque
HOME_DIR2="$TMP_DIR/home2"
STUBS2="$TMP_DIR/stubs"
mkdir -p "$HOME_DIR2/.config/daniel-harness/secrets/tunnels" "$HOME_DIR2/.nvm"
python3 -c "
import yaml; from pathlib import Path
cfg = yaml.safe_load((Path('$ROOT_DIR/examples/config.example.yaml')).read_text())
cfg['models'] = [m for m in cfg['models'] if m.get('trust') != 'restricted']
Path('$HOME_DIR2/.config/daniel-harness/config.yaml').write_text(yaml.dump(cfg))
"
# Fake rm que falla para opencode.json
FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/rm" <<'RMEOF'
#!/bin/bash
for arg in "$@"; do
  if [[ "$arg" == *"opencode.json"* ]]; then
    echo "[fake-rm] Simulated failure for opencode.json" >&2
    exit 1
  fi
done
exec /bin/rm "$@"
RMEOF
chmod +x "$FAKE_BIN/rm"
T5_OUT="$TMP_DIR/t5.out"
set +e
DH_TEST_MODE=1 DH_FAIL_AT=crash-after-config \
  PATH="$FAKE_BIN:$STUBS2:$PATH" HOME="$HOME_DIR2" XDG_CONFIG_HOME="$HOME_DIR2/.config" NVM_DIR="$HOME_DIR2/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$T5_OUT" 2>&1
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  pass "t5: exit $RC (expected non-zero)"
else
  fail "t5: exit 0 (expected failure)"
fi
grep -q 'no se pudo eliminar' "$T5_OUT" 2>/dev/null && pass "t5: rm falló reportado" || fail "t5: rm falló no reportado inesperadamente"
JOURNAL2="$HOME_DIR2/.config/daniel-harness/state/.bootstrap-journal.json"
[[ -f "$JOURNAL2" ]] && pass "t5: journal conservado" || fail "t5: journal eliminado"
# opencode.json existe (mv se ejecutó antes del crash), rm falló al limpiar
OC2="$HOME_DIR2/.config/opencode/opencode.json"
[[ -f "$OC2" ]] && pass "t5: opencode.json existe (antes del crash)" || fail "t5: opencode.json no fue creado"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
