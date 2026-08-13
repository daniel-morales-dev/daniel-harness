#!/usr/bin/env bash
# tests/fail-nvm.test.sh
# Verifica que _install_nvm falla correctamente en escenarios adversos
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

setup_env() {
  local stubs=$1 home=$2
  mkdir -p "$stubs" "$home/.config/daniel-harness/secrets/tunnels" "$home/.nvm"

  cat > "$stubs/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
EOF
  chmod +x "$stubs/sudo"

  cat > "$stubs/apt-get" <<'APTSCRIPT'
#!/bin/bash
exit 0
APTSCRIPT
  chmod +x "$stubs/apt-get"

  cat > "$stubs/dpkg" <<'DPKGSCRIPT'
#!/bin/bash
echo "Status: install ok installed"
exit 0
DPKGSCRIPT
  chmod +x "$stubs/dpkg"

  for tool in node npm opencode codegraph rtk engram gentle-ai dh; do
    cat > "$stubs/$tool" <<'TOOLSCRIPT'
#!/bin/bash
exit 0
TOOLSCRIPT
    chmod +x "$stubs/$tool"
  done

cat > "$stubs/opencode" <<'OPENCODE'
#!/bin/bash
case "$1" in
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) if [[ "$2" == "debug" ]]; then echo "connected"; exit 0; fi ;;
esac
exit 0
OPENCODE
  chmod +x "$stubs/opencode"

  python3 -c "
import yaml
from pathlib import Path
cfg = yaml.safe_load((Path('$ROOT_DIR/examples/config.example.yaml')).read_text())
cfg['models'] = [m for m in cfg['models'] if m.get('trust') != 'restricted']
Path('$home/.config/daniel-harness/config.yaml').write_text(yaml.dump(cfg))
"
}

run_bootstrap() {
  local home=$1 stubs=$2 outfile=$3
  set +e
  HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    TMPDIR="$TMP_DIR/tmp" \
    PATH="$stubs:$PATH" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$outfile" 2>&1
  local rc=$?
  set -e
  return $rc
}

check_no_temps() {
  local leftovers
  leftovers=$(find "$TMP_DIR/tmp" -maxdepth 1 -name 'daniel-harness-nvm.*' 2>/dev/null)
  if [[ -z "$leftovers" ]]; then
    pass "no quedan temporales NVM"
  else
    fail "quedan temporales: $leftovers"
    rm -f "$leftovers"
  fi
}

# --- Test 1: curl falla ---
echo "=== Test 1: curl falla ==="
T1_HOME="$TMP_DIR/home1"
T1_STUBS="$TMP_DIR/stubs1"
T1_OUT="$TMP_DIR/out1"
mkdir -p "$TMP_DIR/tmp"
setup_env "$T1_STUBS" "$T1_HOME"
cat > "$T1_STUBS/curl" <<'EOF'
#!/bin/bash
exit 42
EOF
chmod +x "$T1_STUBS/curl"
run_bootstrap "$T1_HOME" "$T1_STUBS" "$T1_OUT" && \
  fail "t1: bootstrap deberia fallar cuando curl falla" || \
  pass "t1: bootstrap exit != 0 cuando curl falla"
check_no_temps
grep -q 'No se pudo descargar' "$T1_OUT" && pass "t1: menciona descarga fallida" || fail "t1: no menciona descarga fallida"

# --- Test 2: instalador termina no cero ---
echo "=== Test 2: instalador termina con error ==="
T2_HOME="$TMP_DIR/home2"
T2_STUBS="$TMP_DIR/stubs2"
T2_OUT="$TMP_DIR/out2"
setup_env "$T2_STUBS" "$T2_HOME"
cat > "$T2_STUBS/curl" <<'EOF'
#!/bin/bash
outfile=""
while [[ $# -gt 0 ]]; do
  case "$1" in -o|--output) outfile="$2"; shift 2 ;; *) shift ;;
  esac
done
cat > "${outfile:?}" <<'INST'
#!/bin/bash
exit 99
INST
exit 0
EOF
chmod +x "$T2_STUBS/curl"
run_bootstrap "$T2_HOME" "$T2_STUBS" "$T2_OUT" && \
  fail "t2: bootstrap deberia fallar cuando instalador falla" || \
  pass "t2: bootstrap exit != 0 cuando instalador falla"
check_no_temps
grep -q 'El instalador de NVM terminó con error' "$T2_OUT" && \
  pass "t2: menciona error del instalador" || \
  fail "t2: no menciona error del instalador"

# --- Test 3: instalador exitoso pero no crea nvm.sh ---
echo "=== Test 3: instalador no crea nvm.sh ==="
T3_HOME="$TMP_DIR/home3"
T3_STUBS="$TMP_DIR/stubs3"
T3_OUT="$TMP_DIR/out3"
setup_env "$T3_STUBS" "$T3_HOME"
cat > "$T3_STUBS/curl" <<'EOF'
#!/bin/bash
outfile=""
while [[ $# -gt 0 ]]; do
  case "$1" in -o|--output) outfile="$2"; shift 2 ;; *) shift ;;
  esac
done
cat > "${outfile:?}" <<'INST'
#!/bin/bash
exit 0
INST
exit 0
EOF
chmod +x "$T3_STUBS/curl"
run_bootstrap "$T3_HOME" "$T3_STUBS" "$T3_OUT" && \
  fail "t3: bootstrap deberia fallar cuando nvm.sh ausente" || \
  pass "t3: bootstrap exit != 0 cuando nvm.sh ausente"
check_no_temps
grep -q 'NVM no quedó instalado' "$T3_OUT" && \
  pass "t3: menciona NVM no instalado" || \
  fail "t3: no menciona NVM no instalado"

# --- Test 4: exito ---
echo "=== Test 4: instalacion exitosa ==="
T4_HOME="$TMP_DIR/home4"
T4_STUBS="$TMP_DIR/stubs4"
T4_OUT="$TMP_DIR/out4"
setup_env "$T4_STUBS" "$T4_HOME"
create_nvm_curl_stub "$T4_STUBS"
run_bootstrap "$T4_HOME" "$T4_STUBS" "$T4_OUT" && \
  pass "t4: bootstrap exit 0 con instalador valido" || \
  fail "t4: bootstrap fallo con instalador valido"
check_no_temps
[[ -f "$T4_HOME/.nvm/nvm.sh" ]] && pass "t4: nvm.sh existe" || fail "t4: nvm.sh no fue creado"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
