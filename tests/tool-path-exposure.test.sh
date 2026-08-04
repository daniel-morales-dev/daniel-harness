#!/usr/bin/env bash
# tests/tool-path-exposure.test.sh
# Verifica que _ensure_tool_visible expone herramientas en PATH via LOCAL_BIN
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

USE_STUBS=false
for arg in "$@"; do [[ "$arg" == "--stubs" ]] && USE_STUBS=true; done

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

HOME_DIR="$TMP_DIR/home"
LOCAL_BIN="$HOME_DIR/.local/bin"
mkdir -p "$LOCAL_BIN"
export HOME="$HOME_DIR"
export LOCAL_BIN
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export NVM_DIR="$HOME_DIR/.nvm"
export DANIEL_HARNESS_CONFIG_DIR="$HOME_DIR/.config/daniel-harness"
export DANIEL_HARNESS_BIN_DIR="$LOCAL_BIN"
export OPENCODE_CONFIG_DIR="$HOME_DIR/.config/opencode"
export PATH="$LOCAL_BIN:$PATH"

echo "=== Tool Path Exposure Test ==="

# Source _ensure_tool_visible logic (extracted from bootstrap.sh)
_ensure_tool_visible() {
  local name=$1; shift
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  local candidate
  for candidate in "$@"; do
    [[ -x "$candidate" ]] || continue
    if [[ -e "$LOCAL_BIN/$name" ]]; then
      command -v "$name" >/dev/null 2>&1 && return 0
      continue
    fi
    ln -s "$candidate" "$LOCAL_BIN/$name" 2>/dev/null || continue
    if command -v "$name" >/dev/null 2>&1; then
      return 0
    fi
    rm -f "$LOCAL_BIN/$name"
  done
  return 1
}

# install.sh first for dh
bash "$ROOT_DIR/scripts/install.sh" > "$TMP_DIR/install.out" 2>&1 && pass "install.sh OK" || fail "install.sh failed"

# Test 1: Tool already in PATH
echo "--- Test 1: tool already in PATH ---"
touch "$LOCAL_BIN/mocktool"
chmod +x "$LOCAL_BIN/mocktool"
_ensure_tool_visible "mocktool" && pass "mocktool ya en PATH" || fail "mocktool no detectado en PATH"
rm -f "$LOCAL_BIN/mocktool"

# Test 2: Tool en location no-PATH, create symlink
echo "--- Test 2: symlink desde location no-PATH ---"
mkdir -p "$HOME_DIR/.custom/bin"
echo '#!/bin/sh' > "$HOME_DIR/.custom/bin/opencode-stub"
chmod +x "$HOME_DIR/.custom/bin/opencode-stub"
_ensure_tool_visible "opencode-stub" "$HOME_DIR/.custom/bin/opencode-stub" && pass "symlink creado para opencode-stub" || fail "symlink fallo para opencode-stub"
if [[ -L "$LOCAL_BIN/opencode-stub" ]]; then
  pass "symlink verificado" 
else
  fail "symlink no existe en LOCAL_BIN"
fi
command -v opencode-stub >/dev/null 2>&1 && pass "opencode-stub disponible en PATH" || fail "opencode-stub no en PATH"

# Test 3: Binary does not exist at any candidate
echo "--- Test 3: binario no existe ---"
_ensure_tool_visible "nonexistent-tool" "$HOME_DIR/.custom/bin/nonexistent-tool" && fail "deberia fallar" || pass "fallo correctamente para binario inexistente"

# Test 4: Idempotence — second call should succeed
echo "--- Test 4: idempotencia ---"
_ensure_tool_visible "opencode-stub" "$HOME_DIR/.custom/bin/opencode-stub" && pass "segunda llamada idempotente" || fail "segunda llamada fallo"

# Test 5: Existing file in LOCAL_BIN prevents override
echo "--- Test 5: preservar archivo existente ---"
echo '#!/bin/sh' > "$LOCAL_BIN/protected-tool"
chmod +x "$LOCAL_BIN/protected-tool"
PROTECTED_INODE=$(stat -c '%i' "$LOCAL_BIN/protected-tool")
mkdir -p "$HOME_DIR/.other/bin"
echo '#!/bin/sh' > "$HOME_DIR/.other/bin/protected-tool"
chmod +x "$HOME_DIR/.other/bin/protected-tool"
_ensure_tool_visible "protected-tool" "$HOME_DIR/.other/bin/protected-tool"
AFTER_INODE=$(stat -c '%i' "$LOCAL_BIN/protected-tool")
if [[ "$PROTECTED_INODE" == "$AFTER_INODE" ]]; then
  pass "archivo existente preservado"
else
  fail "archivo existente fue modificado"
fi

# Test 6: Multiple candidates, first missing, second works
echo "--- Test 6: multiples candidatos ---"
mkdir -p "$HOME_DIR/.alt/bin"
echo '#!/bin/sh' > "$HOME_DIR/.alt/bin/multi-tool"
chmod +x "$HOME_DIR/.alt/bin/multi-tool"
_ensure_tool_visible "multi-tool" \
  "$HOME_DIR/.fake/nonexistent" \
  "$HOME_DIR/.alt/bin/multi-tool" \
  && pass "segundo candidato funciona" || fail "segundo candidato fallo"

# Test 7: dh debe ser visible (por install.sh)
echo "--- Test 7: dh en PATH ---"
command -v dh >/dev/null 2>&1 && pass "dh disponible en PATH" || fail "dh no disponible"

# Test 8: Stubs mode — simulate bootstrap flow
if $USE_STUBS; then
  echo "--- Test 8: bootstrap con stubs ---"
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core --dry-run > "$TMP_DIR/boot.out" 2>&1
  grep -q 'Bootstrap completado' "$TMP_DIR/boot.out" && pass "dry-run bootstrap completado" || fail "dry-run bootstrap fallo"
fi

echo ""
echo "=== Tool Path Exposure Test: $PASS pass, $FAIL fail ==="
(( FAIL == 0 ))
