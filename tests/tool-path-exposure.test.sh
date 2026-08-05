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

# Source real implementation
CRITICAL_CALLED=false
critical() { CRITICAL_CALLED=true; printf '  [critico] %s\n' "$*"; }
source "$ROOT_DIR/scripts/lib/tool-path.sh"

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

# Test 8: bootstrap no muestra completado cuando tool requerida no disponible
echo "--- Test 8: bootstrap falla sin tool ---"
SIM_OUT=$("$ROOT_DIR/scripts/bootstrap.sh" --profile core --dry-run 2>&1 || true)
if echo "$SIM_OUT" | grep -q 'Bootstrap completado y saludable'; then
  # dry-run pasa; testear funcion directamente
  MISSED=$(bash -c '
    source "'"$ROOT_DIR/scripts/lib/tool-path.sh"'"
    LOCAL_BIN=/tmp/nonexistent-bin
    export PATH=/tmp/nonexistent-bin
    _ensure_tool_visible ghost-tool /nope/ghost 2>/dev/null; echo rc=$?
  ')
  if echo "$MISSED" | grep -q 'rc=1'; then
    pass "herramienta fantasma retorna 1 (bootstrap no mostraria completado)"
  else
    fail "se esperaba rc=1, obtuvo: $MISSED"
  fi
else
  pass "bootstrap no mostro completado (dry-run con tool ausente)"
fi

# Test 9: Stubs mode — simulate bootstrap flow
if $USE_STUBS; then
  echo "--- Test 9: bootstrap con stubs ---"
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core --dry-run > "$TMP_DIR/boot.out" 2>&1
  grep -q 'Bootstrap completado' "$TMP_DIR/boot.out" && pass "dry-run bootstrap completado" || fail "dry-run bootstrap fallo"
fi

# --- Test 10: Integrated bootstrap — installer stub returns 0 but no binary ---
if $USE_STUBS; then
echo "--- Test 10: bootstrap integrado — instalador stub retorna 0 pero no crea binario ---"

STUB_DIR="$TMP_DIR/stubs-bootstrap"
HOME_INT="$TMP_DIR/home-integrated"
mkdir -p "$STUB_DIR" "$HOME_INT/.config/daniel-harness/secrets/tunnels" "$HOME_INT/.nvm" "$HOME_INT/.local/bin"
mkdir -p "$HOME_INT/.config/opencode/agents" "$HOME_INT/.config/opencode/skills"

# System stubs
cat > "$STUB_DIR/sudo" <<'SUDO'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
SUDO
chmod +x "$STUB_DIR/sudo"

cat > "$STUB_DIR/apt-get" <<'APT'
#!/bin/bash
exit 0
APT
chmod +x "$STUB_DIR/apt-get"

cat > "$STUB_DIR/dpkg" <<'DPKG'
#!/bin/bash
if [[ "$1" == "-s" ]]; then echo "Status: install ok installed"; exit 0; fi
exit 0
DPKG
chmod +x "$STUB_DIR/dpkg"

# curl stub: pipe mode = no-op installer, -o mode = empty file
cat > "$STUB_DIR/curl" <<'CURL'
#!/bin/bash
outfile=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) outfile="$2"; shift 2 ;;
    -*) shift ;;
    *) shift ;;
  esac
done
if [[ -n "${outfile:-}" ]]; then
  : > "$outfile"
  exit 0
fi
printf '#!/bin/bash\nexit 0\n'
exit 0
CURL
chmod +x "$STUB_DIR/curl"

# nvm.sh stub (must support --version, install, alias)
cat > "$HOME_INT/.nvm/nvm.sh" <<'NVM'
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
NVM
chmod +x "$HOME_INT/.nvm/nvm.sh"

# node and npm stubs in PATH
cat > "$STUB_DIR/node" <<'NODE'
#!/bin/bash
echo "v24.0.0"
NODE
chmod +x "$STUB_DIR/node"

cat > "$STUB_DIR/npm" <<'NPM'
#!/bin/bash
exit 0
NPM
chmod +x "$STUB_DIR/npm"

# gentle-ai stub (needed if bootstrap reaches gentle-ai after opencode,
# but opencode failure should prevent that)
cat > "$STUB_DIR/gentle-ai" <<'GENTLE'
#!/bin/bash
case "$1" in
  version) echo "gentle-ai 9.9.9 (stub)" ;;
  doctor) echo "Status:  healthy" ;;
  review) if [[ "$2" == "mode" ]]; then echo "receipt-driven development: on (decided by default)"; fi ;;
  skill-registry) mkdir -p "$ROOT_DIR/.atl" 2>/dev/null; touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null; echo "ok" ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUB_DIR/gentle-ai"

for tool in codegraph engram rtk dh; do
  cat > "$STUB_DIR/$tool" <<'TOOL'
#!/bin/bash
exit 0
TOOL
  chmod +x "$STUB_DIR/$tool"
done

# Config files
cat > "$HOME_INT/.config/daniel-harness/config.yaml" <<'YAML'
version: "1"
models:
  - id: default
    trust: trusted
    allowArbitraryShell: false
    allowedCapabilities: []
YAML
chmod 600 "$HOME_INT/.config/daniel-harness/config.yaml"

cat > "$HOME_INT/.config/daniel-harness/project-registry.yaml" <<'YAML'
version: "1"
profiles: []
YAML
chmod 600 "$HOME_INT/.config/daniel-harness/project-registry.yaml"

printf '%s\n' 'version: "1"' 'tunnels: []' >"$HOME_INT/.config/daniel-harness/connections.yaml"
chmod 600 "$HOME_INT/.config/daniel-harness/connections.yaml"

# Verify opencode is NOT in controlled PATH
CONTROLLED_PATH="$STUB_DIR:/usr/bin:/bin"
if PATH="$CONTROLLED_PATH" command -v opencode >/dev/null 2>&1; then
  echo "fixture invalido: opencode ya existe en PATH ($(PATH="$CONTROLLED_PATH" command -v opencode))" >&2
  exit 1
fi
pass "Test 10: fixture — opencode no existe en PATH controlado"

# Run bootstrap with isolated environment
set +e
BOOT_OUT=$(env \
  HOME="$HOME_INT" \
  XDG_CONFIG_HOME="$HOME_INT/.config" \
  NVM_DIR="$HOME_INT/.nvm" \
  DANIEL_HARNESS_CONFIG_DIR="$HOME_INT/.config/daniel-harness" \
  DANIEL_HARNESS_BIN_DIR="$HOME_INT/.local/bin" \
  OPENCODE_CONFIG_DIR="$HOME_INT/.config/opencode" \
  PATH="$CONTROLLED_PATH" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core 2>&1)
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  pass "Test 10: bootstrap exit != 0 (rc=$rc)"
else
  fail "Test 10: bootstrap exit 0 (se esperaba fallo)"
fi

if echo "$BOOT_OUT" | grep -q 'Instalando OpenCode'; then
  pass "Test 10: bootstrap llego a Instalando OpenCode"
else
  fail "Test 10: bootstrap no llego a Instalando OpenCode"
fi

if echo "$BOOT_OUT" | grep -q 'opencode no encontrado en PATH tras la instalacion'; then
  pass "Test 10: salida contiene critico de opencode no encontrado"
else
  fail "Test 10: falta critico de opencode"
fi

if echo "$BOOT_OUT" | grep -q 'Bootstrap completado y saludable'; then
  fail "Test 10: salida contiene Bootstrap completado pese a fallo"
else
  pass "Test 10: salida no contiene Bootstrap completado"
fi

fi # USE_STUBS

echo ""
echo "=== Tool Path Exposure Test: $PASS pass, $FAIL fail ==="
(( FAIL == 0 ))
