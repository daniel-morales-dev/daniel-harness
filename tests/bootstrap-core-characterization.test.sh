#!/usr/bin/env bash
# Characterization: bootstrap --profile core con HOME aislado
# Bucle principal de depuración antes de E2E completo.
# DH_DEBUG_BOOTSTRAP=1 habilita bash -x con PS4 detallado.
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)

cleanup_test_tmp() {
  if [[ "${DH_KEEP_TEST_TMP:-0}" == "1" ]]; then
    printf '%s\n' "TMP_DIR preservado: $TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup_test_tmp EXIT

HOME_CORE="$TMP_DIR/home-core"
STUBS="$TMP_DIR/stubs"
mkdir -p "$HOME_CORE" "$STUBS" "$HOME_CORE/.nvm"

create_nvm_curl_stub "$STUBS"

cat > "$STUBS/sudo" <<'SUDO'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
SUDO
chmod +x "$STUBS/sudo"

for tool in apt-get dpkg node npm opencode gentle-ai codegraph rtk engram dh; do
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/$tool"
  chmod +x "$STUBS/$tool"
done

printf '#!/bin/bash\nif [[ "$1" == "-s" ]]; then echo "Status: install ok installed"; exit 0; fi\nexit 0\n' > "$STUBS/dpkg"
chmod +x "$STUBS/dpkg"

printf '#!/bin/bash\necho "v24.0.0"; exit 0\n' > "$STUBS/node"
chmod +x "$STUBS/node"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
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
  version) echo "gentle-ai 9.9.9 (stub)" ;;
  doctor) echo "Status:  healthy" ;;
  review) if [[ "$2" == "mode" ]]; then echo "receipt-driven development: on (decided by default)"; fi ;;
  skill-registry) mkdir -p "$ROOT_DIR/.atl" 2>/dev/null; touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null; echo "ok" ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUBS/gentle-ai"

mkdir -p "$HOME_CORE/.config/daniel-harness/secrets/tunnels"
cat > "$HOME_CORE/.config/daniel-harness/config.yaml" <<'YAML'
version: "1"
models:
  - id: default
    trust: trusted
    allowArbitraryShell: false
    allowedCapabilities: []
YAML

export PATH="$STUBS:$PATH"
export DH_TEST_MODE=1
export DH_TRANSACTION_ALLOW_TMP=1

# ── Ejecutar bootstrap core ──────────────────────────────────
printf '\n=== Characterization: bootstrap --profile core ===\n'

if [[ "${DH_DEBUG_BOOTSTRAP:-0}" == "1" ]]; then
  PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]:-main}: '
  export PS4
  set -x
fi

BOOT_OUT="$TMP_DIR/boot.stdout"
BOOT_ERR="$TMP_DIR/boot.stderr"

env HOME="$HOME_CORE" PATH="$STUBS:$PATH" XDG_CONFIG_HOME="$HOME_CORE/.config" NVM_DIR="$HOME_CORE/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core >"$BOOT_OUT" 2>"$BOOT_ERR"; rc=$?

if [[ "${DH_DEBUG_BOOTSTRAP:-0}" == "1" ]]; then
  set +x
fi

printf '\n--- exit code: %s ---\n' "$rc"
if [[ $rc -ne 0 ]]; then
  printf '%s\n' '--- stdout ---'
  cat "$BOOT_OUT"
  printf '%s\n' '--- stderr ---'
  cat "$BOOT_ERR"
  printf '%s\n' '--- journal ---'
  local jf="$HOME_CORE/.config/daniel-harness/state/.bootstrap-journal.json"
  if [[ -f "$jf" ]]; then
    jq '{journalVersion,phase,resources: [.resources[]?|{id,applyOrder,status,resourceType,existedBefore}]}' "$jf" 2>/dev/null || cat "$jf"
  else
    printf '%s\n' '(sin journal)'
  fi
  printf '\nFAIL: bootstrap core rc=%s\n' "$rc"
  exit 1
fi

# ── Validaciones ─────────────────────────────────────────────
PASS=0
FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

printf '\n--- Validaciones post-bootstrap ---\n'

# opencode.json
OC_FILE="$HOME_CORE/.config/opencode/opencode.json"
[[ -f "$OC_FILE" ]] && pass "opencode.json existe" || fail "opencode.json no existe"
jq empty "$OC_FILE" 2>/dev/null && pass "JSON válido" || fail "JSON inválido"

# Journal eliminado
JF="$HOME_CORE/.config/daniel-harness/state/.bootstrap-journal.json"
[[ ! -f "$JF" ]] && pass "journal eliminado" || {
  fail "journal residual"
  cat "$JF"
}

# Agentes
AGENT_DIR="$HOME_CORE/.config/opencode/agents"
for a in alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  [[ -f "$AGENT_DIR/$a.md" ]] && pass "agente $a" || fail "agente $a faltante"
done

# Managed state
ST_FILE="$HOME_CORE/.config/daniel-harness/state/opencode-managed.state"
[[ -f "$ST_FILE" ]] && pass "managed state existe" || fail "managed state faltante"

# Ponytail plugin
jq -e '.plugin[] | startswith("@dietrichgebert/ponytail")' "$OC_FILE" >/dev/null && pass "Ponytail registrado" || fail "Ponytail faltante"

# MCPs core
for m in codegraph engram; do
  jq -e ".mcp | has(\"$m\")" "$OC_FILE" >/dev/null && pass "MCP $m" || fail "MCP $m faltante"
done

# MCPs NO core
for m in linear github context7 wiki-alegra; do
  jq -e ".mcp | has(\"$m\")" "$OC_FILE" >/dev/null && fail "MCP $m no debiera estar en core" || pass "MCP $m correctamente ausente"
done

# Doctor install-check
if command -v opencode >/dev/null 2>&1; then
  env HOME="$HOME_CORE" PATH="$STUBS:$PATH" XDG_CONFIG_HOME="$HOME_CORE/.config" \
    bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict --install-check --skip-oauth >"$TMP_DIR/doctor.stdout" 2>"$TMP_DIR/doctor.stderr" && \
    pass "doctor install-check ok" || {
      cat "$TMP_DIR/doctor.stdout"
      fail "doctor install-check falló"
    }
fi

# stderr visible (no silenciado por exec)
if [[ -s "$BOOT_ERR" ]]; then
  pass "stderr contiene salida (visible)"
else
  fail "stderr vacío — posible redirección silenciosa"
fi

printf '\n========================================\n'
printf '  Resultados: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
