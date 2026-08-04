#!/usr/bin/env bash
# E2E: bootstrap real con stubs en HOME aislado
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_TMP="$TMP_DIR/home"
CONFIG_TMP="$TMP_DIR/config"
STUBS="$TMP_DIR/stubs"
OC_FILE="$CONFIG_TMP/opencode/opencode.json"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

# --- Setup: stubs and fake HOME ---
printf '=== Setup: stubs ===\n'
mkdir -p "$STUBS" "$HOME_TMP" "$HOME_TMP/.nvm" "$CONFIG_TMP"

# Stub sudo — acepta cualquier flag, exit 0
cat > "$STUBS/sudo" <<'SUDO'
#!/bin/bash
# ponytail: sudo stub — filtra flags y ejecuta el comando
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
SUDO
chmod +x "$STUBS/sudo"

# Stub apt-get — exit 0 sin instalar
cat > "$STUBS/apt-get" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUBS/apt-get"

# Stub dpkg — todos los paquetes reportados como instalados
cat > "$STUBS/dpkg" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]]; then
  echo "Status: install ok installed"
  exit 0
fi
exit 0
EOF
chmod +x "$STUBS/dpkg"

# Stub curl — output script que crea nvm.sh
cat > "$STUBS/curl" <<'EOF'
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
EOF
chmod +x "$STUBS/curl"

# Stub node
cat > "$STUBS/node" <<'NODE'
#!/bin/bash
echo "v24.0.0"
exit 0
NODE
chmod +x "$STUBS/node"

# Stub npm
cat > "$STUBS/npm" <<'NPM'
#!/bin/bash
exit 0
NPM
chmod +x "$STUBS/npm"

# Stub opencode — responde a mcp debug
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then
  echo "connected"
  exit 0
fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

# Stub gentle-ai
# ponytail: $ROOT_DIR expandido por shell al crear stub para que funcione
# dentro del subshell del bootstrap sin export
cat > "$STUBS/gentle-ai" <<GENTLE
#!/bin/bash
case "\$1" in
  version) echo "gentle-ai 9.9.9 (stub)" ;;
  doctor) echo "Status:  healthy" ;;
  review)
    if [[ "\$2" == "mode" ]]; then
      echo "receipt-driven development: on (decided by default)"
    fi
    ;;
  skill-registry)
    mkdir -p "$ROOT_DIR/.atl" 2>/dev/null
    touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null
    echo "ok"
    ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUBS/gentle-ai"

# Stub codegraph
cat > "$STUBS/codegraph" <<'CODEGRAPH'
#!/bin/bash
exit 0
CODEGRAPH
chmod +x "$STUBS/codegraph"

# Stub rtk
cat > "$STUBS/rtk" <<'RTK'
#!/bin/bash
exit 0
RTK
chmod +x "$STUBS/rtk"

# Stub dh
cat > "$STUBS/dh" <<'DH'
#!/bin/bash
echo "dh stub"
exit 0
DH
chmod +x "$STUBS/dh"

# Stub engram
cat > "$STUBS/engram" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUBS/engram"

# Pre-crear archivos de comando de túneles para evitar warnings en doctor
mkdir -p "$CONFIG_TMP/daniel-harness/secrets/tunnels"
for tunnel in alegra-hopper alegra-production k-agencia-mysql k-agencia-mongodb k-agencia-garage; do
  printf 'echo %s tunnel stub\n' "$tunnel" > "$CONFIG_TMP/daniel-harness/secrets/tunnels/$tunnel.command"
  chmod 600 "$CONFIG_TMP/daniel-harness/secrets/tunnels/$tunnel.command"
done

# Pre-crear nvm.sh para que bootstrap lo detecte como instalado
cat > "$HOME_TMP/.nvm/nvm.sh" <<'NVMINIT'
nvm() {
  case "$1" in
    --version) echo "0.40.4" ;;
    install) ;;
    alias) ;;
    *) ;;
  esac
}
NVMINIT

# Pre-crear config.yaml sin restricted trust para evitar falsos críticos en doctor
cat > "$CONFIG_TMP/daniel-harness/config.yaml" <<'EOF'
version: "1"
trust: trusted
EOF

export PATH="$STUBS:$PATH"
export HOME="$HOME_TMP"
export XDG_CONFIG_HOME="$CONFIG_TMP"
export NVM_DIR="$HOME_TMP/.nvm"

# --- Phase 1: Bootstrap --profile core for real ---
printf '\n=== Phase 1: bootstrap --profile core ===\n'
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/bootstrap.out" 2>&1 || true
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap.out" && pass "bootstrap core completed healthy" || {
  cat "$TMP_DIR/bootstrap.out"
  fail "bootstrap core failed"
}

# --- Phase 2: Validate opencode.json ---
printf '\n=== Phase 2: opencode.json validation ===\n'
jq empty "$OC_FILE" && pass "opencode.json is valid JSON" || fail "opencode.json is not valid JSON"

# Validate structure
[[ $(jq 'has("mcp")' "$OC_FILE") == "true" ]] && pass "mcp section exists" || fail "mcp section missing"
[[ $(jq 'has("plugin")' "$OC_FILE") == "true" ]] && pass "plugin section exists" || fail "plugin section missing"

# Validate profile core MCPs are present
jq -e '.mcp | has("codegraph")' "$OC_FILE" >/dev/null && pass "MCP codegraph configured" || fail "MCP codegraph missing"
jq -e '.mcp | has("engram")' "$OC_FILE" >/dev/null && pass "MCP engram configured" || fail "MCP engram missing"
jq -e '.mcp | has("linear") | not' "$OC_FILE" >/dev/null && pass "MCP linear not in core" || fail "MCP linear should not be in core"

# Validate Ponytail plugin
jq -e '.plugin | index("@dietrichgebert/ponytail@latest") != null' "$OC_FILE" >/dev/null && pass "Ponytail plugin registered" || fail "Ponytail plugin missing"

# Validate MCP types
jq -e '.mcp.codegraph.type == "local"' "$OC_FILE" >/dev/null && pass "codegraph is local" || fail "codegraph type mismatch"
jq -e '.mcp.engram.type == "local"' "$OC_FILE" >/dev/null && pass "engram is local" || fail "engram type mismatch"

# Validate no disabledTools anywhere in MCP config
jq -e '[.mcp[] | has("disabledTools")] | any | not' "$OC_FILE" >/dev/null && pass "no MCP has disabledTools" || fail "some MCP still has disabledTools"

# --- Phase 3: Validate agents and skills installed ---
printf '\n=== Phase 3: Agents and skills ===\n'
[[ -L "$CONFIG_TMP/opencode/agents/alegra-microservice-engineer.md" ]] && pass "agent alegra-microservice-engineer" || fail "agent alegra-microservice-engineer missing"
[[ -L "$CONFIG_TMP/opencode/agents/code-reviewer.md" ]] && pass "agent code-reviewer" || fail "agent code-reviewer missing"
[[ -L "$CONFIG_TMP/opencode/agents/alegra-microservice-test-engineer.md" ]] && pass "agent alegra-microservice-test-engineer" || fail "agent alegra-microservice-test-engineer missing"
[[ -L "$CONFIG_TMP/opencode/agents/php-engineer.md" ]] && pass "agent php-engineer" || fail "agent php-engineer missing"
[[ -L "$CONFIG_TMP/opencode/agents/migration-parity-reviewer.md" ]] && pass "agent migration-parity-reviewer" || fail "agent migration-parity-reviewer missing"
[[ -d "$CONFIG_TMP/opencode/skills/monolith-to-micro-migration" ]] && pass "skill monolith-to-micro-migration" || fail "skill monolith-to-micro-migration missing"
[[ -d "$CONFIG_TMP/opencode/skills/task-lifecycle" ]] && pass "skill task-lifecycle" || fail "skill task-lifecycle missing"
[[ -f "$CONFIG_TMP/opencode/commands/migration-gap-analysis.md" ]] && pass "command migration-gap-analysis" || fail "command migration-gap-analysis missing"
[[ -L "$HOME_TMP/.local/bin/dh" ]] && pass "dh CLI linked" || fail "dh CLI missing"

# --- Phase 4: Doctor --profile core --strict ---
printf '\n=== Phase 4: doctor --profile core --strict ===\n'
bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict > "$TMP_DIR/doctor.out" 2>&1 || true
grep -q 'Resumen: 0 crítico(s)' "$TMP_DIR/doctor.out" && pass "doctor --profile core --strict passed" || {
  cat "$TMP_DIR/doctor.out"
  fail "doctor reported criticals"
}

# --- Phase 5: Idempotence (second bootstrap makes no changes) ---
printf '\n=== Phase 5: Idempotence ===\n'
FIRST_HASH=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" 2>/dev/null | cut -d' ' -f1 || echo none)
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/bootstrap2.out" 2>&1 || true
SECOND_HASH=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" 2>/dev/null | cut -d' ' -f1 || echo none)
[[ "$FIRST_HASH" == "$SECOND_HASH" ]] && pass "second bootstrap is idempotent (config unchanged)" || fail "second bootstrap modified config"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap2.out" && pass "second bootstrap healthy" || fail "second bootstrap failed"

# --- Phase 6: Profile manifest validation ---
printf '\n=== Phase 6: Profile manifest validation ===\n'
for profile in core alegra migration full; do
  awk -v p="$profile" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { found=1; exit }
  ' "$ROOT_DIR/bootstrap/manifest.yaml" && pass "profile $profile exists in manifest" || fail "profile $profile missing from manifest"
done

# --- Phase 7: Bootstrap --profile core --connect (auth interactivo) ---
printf '\n=== Phase 7: bootstrap --profile core --connect ===\n'
bash "$ROOT_DIR/install" --profile core --connect > "$TMP_DIR/connect.out" 2>&1 || true
grep -q 'autenticado\|no requiere OAuth' "$TMP_DIR/connect.out" && pass "--connect runs auth steps" || {
  cat "$TMP_DIR/connect.out"
  fail "--connect did not run auth"
}
grep -q 'GITHUB_PERSONAL_ACCESS_TOKEN' "$TMP_DIR/connect.out" && pass "--connect checks GH PAT" || fail "--connect did not check GH PAT"

# --- Phase 8: Bootstrap --dry-run for alegra profile ---
printf '\n=== Phase 8: bootstrap --dry-run alegra ===\n'
bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile alegra > "$TMP_DIR/bootstrap-alegra.out" 2>&1 || true
grep -q 'Bootstrap completado' "$TMP_DIR/bootstrap-alegra.out" && pass "alegra dry-run completes" || fail "alegra dry-run failed"
grep -q 'disabledTools' "$TMP_DIR/bootstrap-alegra.out" && fail "alegra dry-run still has disabledTools" || pass "alegra dry-run has no disabledTools"
# --- Phase 9: Doctor MCP live check (auth-required) ---
printf '\n=== Phase 9: Doctor MCP live check ===\n'
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then
  echo "auth-required"
  exit 0
fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict > "$TMP_DIR/doctor-auth.out" 2>&1 || true
grep -q 'requiere autenticacion' "$TMP_DIR/doctor-auth.out" && pass "doctor detects auth-required MCP" || {
  cat "$TMP_DIR/doctor-auth.out"
  fail "doctor did not flag auth-required MCP"
}
grep -q 'crítico' "$TMP_DIR/doctor-auth.out" && pass "doctor reports criticals for auth-required" || fail "doctor should have criticals"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then
  echo "connected"
  exit 0
fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

# --- Summary ---
printf '\n========================================\n'
printf '  Resultados: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
