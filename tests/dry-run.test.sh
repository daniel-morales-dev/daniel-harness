#!/usr/bin/env bash
# tests/dry-run.test.sh
# P1: --help y --dry-run no deben modificar el filesystem
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

# snapshot del árbol de archivos antes/después
tree_before() {
  TREE_BEFORE=$(find "$HOME_DIR" -type f -o -type d 2>/dev/null | sort || echo "")
}

tree_unchanged() {
  local label=$1
  TREE_AFTER=$(find "$HOME_DIR" -type f -o -type d 2>/dev/null | sort || echo "")
  if [[ "$TREE_BEFORE" == "$TREE_AFTER" ]]; then
    pass "$label: filesystem unchanged"
  else
    fail "$label: filesystem CHANGED"
  fi
}

# --- Setup: HOME limpio ---
HOME_DIR="$TMP_DIR/home-clean"
mkdir -p "$HOME_DIR"
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export NVM_DIR="$HOME_DIR/.nvm"

echo "=== Test 1: --help no modifica nada ==="
tree_before
set +e
timeout 30 bash "$ROOT_DIR/scripts/bootstrap.sh" --help > /dev/null 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]]; then pass "help exit code 0"; else fail "help exit code $RC"; fi
tree_unchanged "help"

echo "=== Test 2: --dry-run --profile core no modifica nada ==="
tree_before
set +e
timeout 60 bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile core > /dev/null 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]] || [[ $RC -eq 1 ]]; then pass "dry-run core exit code $RC (acceptable)"; else fail "dry-run core exit code $RC (unexpected)"; fi
tree_unchanged "dry-run core"

echo "=== Test 3: --dry-run --profile alegra no modifica nada ==="
tree_before
set +e
timeout 60 bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile alegra > /dev/null 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]] || [[ $RC -eq 1 ]]; then pass "dry-run alegra exit code $RC"; else fail "dry-run alegra exit code $RC"; fi
tree_unchanged "dry-run alegra"

echo "=== Test 4: --dry-run --profile migration --skip-docker no modifica nada ==="
tree_before
set +e
timeout 60 bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile migration --skip-docker > /dev/null 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]] || [[ $RC -eq 1 ]]; then pass "dry-run migration exit code $RC"; else fail "dry-run migration exit code $RC"; fi
tree_unchanged "dry-run migration"

echo "=== Test 5: --dry-run --profile full no modifica nada ==="
tree_before
set +e
timeout 60 bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile full > /dev/null 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]] || [[ $RC -eq 1 ]]; then pass "dry-run full exit code $RC"; else fail "dry-run full exit code $RC"; fi
tree_unchanged "dry-run full"

echo "=== Test 6: output contiene simulación ==="
OUTPUT="$TMP_DIR/dry-run-output.txt"
set +e
timeout 60 bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile core > "$OUTPUT" 2>&1
set -e
grep -q '\[simulado\]' "$OUTPUT" && pass "dry-run muestra simulación" || fail "dry-run no muestra simulación"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
