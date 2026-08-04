#!/usr/bin/env bash
# tests/fail-nvm.test.sh
# Verifica que _install_nvm falla correctamente en escenarios adversos
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

setup_stubs() {
  local stubs=$1 curl_script=$2
  mkdir -p "$stubs"

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

  printf '%s' "$curl_script" > "$stubs/curl"
  chmod +x "$stubs/curl"

  for tool in node npm opencode codegraph rtk engram gentle-ai dh; do
    cat > "$stubs/$tool" <<'TOOLSCRIPT'
#!/bin/bash
exit 0
TOOLSCRIPT
    chmod +x "$stubs/$tool"
  done
}

check_no_temps() {
  local leftovers
  leftovers=$(find /tmp -maxdepth 1 -name 'daniel-harness-nvm.*' 2>/dev/null)
  if [[ -z "$leftovers" ]]; then
    pass "no quedan temporales NVM"
  else
    fail "quedan temporales: $leftovers"
    rm -f "$leftovers"
  fi
}

run_and_capture() {
  local home=$1 stubs=$2 outfile=$3
  set +e
  {
    HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
      PATH="$stubs:$PATH" \
      bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core 2>&1
    echo "EXIT_CODE=$?"
  } > "$outfile"
  set -e
}

# --- Test 1: curl falla ---
echo "=== Test: curl falla al descargar NVM ==="
HOME1=$(mktemp -d)
STUBS1=$(mktemp -d)
OUT1="$TMP_DIR/out1"
setup_stubs "$STUBS1" '#!/bin/bash
exit 42'
run_and_capture "$HOME1" "$STUBS1" "$OUT1"
output=$(cat "$OUT1")
rc=$(echo "$output" | grep 'EXIT_CODE=' | tail -1 | sed 's/.*EXIT_CODE=//')
check_no_temps
if [[ "$rc" -ne 0 ]]; then
  pass "bootstrap exit != 0 cuando curl falla"
else
  fail "bootstrap deberia fallar cuando curl falla"
fi
if echo "$output" | grep -q 'Bootstrap completado'; then
  fail "no debe imprimir Bootstrap completado cuando curl falla"
else
  pass "no imprime Bootstrap completado cuando curl falla"
fi
rm -rf "$HOME1" "$STUBS1"

# --- Test 2: instalador descargado termina no cero ---
echo "=== Test: instalador NVM termina con error ==="
HOME2=$(mktemp -d)
STUBS2=$(mktemp -d)
OUT2="$TMP_DIR/out2"
setup_stubs "$STUBS2" '#!/bin/bash
exit 99'
run_and_capture "$HOME2" "$STUBS2" "$OUT2"
output=$(cat "$OUT2")
rc=$(echo "$output" | grep 'EXIT_CODE=' | tail -1 | sed 's/.*EXIT_CODE=//')
check_no_temps
if [[ "$rc" -ne 0 ]]; then
  pass "bootstrap exit != 0 cuando instalador falla"
else
  fail "bootstrap deberia fallar cuando instalador falla"
fi
if echo "$output" | grep -q 'Bootstrap completado'; then
  fail "no debe imprimir Bootstrap completado cuando instalador falla"
else
  pass "no imprime Bootstrap completado cuando instalador falla"
fi
rm -rf "$HOME2" "$STUBS2"

# --- Test 3: instalador devuelve 0 pero no crea nvm.sh ---
echo "=== Test: instalador exitoso pero nvm.sh ausente ==="
HOME3=$(mktemp -d)
STUBS3=$(mktemp -d)
OUT3="$TMP_DIR/out3"
setup_stubs "$STUBS3" '#!/bin/bash
exit 0'
run_and_capture "$HOME3" "$STUBS3" "$OUT3"
output=$(cat "$OUT3")
rc=$(echo "$output" | grep 'EXIT_CODE=' | tail -1 | sed 's/.*EXIT_CODE=//')
check_no_temps
if [[ "$rc" -ne 0 ]]; then
  pass "bootstrap exit != 0 cuando nvm.sh no se crea"
else
  fail "bootstrap deberia fallar cuando nvm.sh ausente"
fi
if echo "$output" | grep -q 'Bootstrap completado'; then
  fail "no debe imprimir Bootstrap completado cuando nvm.sh ausente"
else
  pass "no imprime Bootstrap completado cuando nvm.sh ausente"
fi
rm -rf "$HOME3" "$STUBS3"

echo ""
echo "=== Resultados NVM fails: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
