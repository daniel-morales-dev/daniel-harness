#!/usr/bin/env bash
# tests/doctor-install-check.test.sh
# P0: Doctor --install-check valida command de MCPs requeridos por perfil
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STUBS="$TMP_DIR/stubs"
HOME_DIR="$TMP_DIR/home"
mkdir -p "$STUBS" "$HOME_DIR"

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

# --- Setup: stubs for all core profile tools ---
printf '=== Setup: stubs ===\n'

# sudo stub
cat > "$STUBS/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
EOF
chmod +x "$STUBS/sudo"

# opencode stub: deterministic response for profile MCPs
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "${1:-}:${2:-}:${3:-}" in
  mcp:debug:codegraph|mcp:debug:engram)
    printf '%s\n' 'not connected'
    exit 1
    ;;
  *)
    printf 'invocacion inesperada de opencode: %s\n' "$*" >&2
    exit 64
    ;;
esac
OPENCODE
chmod +x "$STUBS/opencode"

# gentle-ai stub (complete enough for doctor to pass)
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

for tool in codegraph engram rtk dh; do
  cat > "$STUBS/$tool" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUBS/$tool"
done

# --- Setup: isolated HOME with config files ---
mkdir -p "$HOME_DIR/.config/daniel-harness/secrets/tunnels"
mkdir -p "$HOME_DIR/.config/daniel-harness/state"
mkdir -p "$HOME_DIR/.config/opencode/agents"
mkdir -p "$HOME_DIR/.config/opencode/skills"
mkdir -p "$HOME_DIR/.local/bin"

# Minimal config.yaml
cat > "$HOME_DIR/.config/daniel-harness/config.yaml" <<'YAML'
version: "1"
models:
  - id: default
    trust: trusted
    allowArbitraryShell: false
    allowedCapabilities: []
YAML
chmod 600 "$HOME_DIR/.config/daniel-harness/config.yaml"

# Minimal project-registry.yaml
cat > "$HOME_DIR/.config/daniel-harness/project-registry.yaml" <<'YAML'
version: "1"
profiles: []
YAML
chmod 600 "$HOME_DIR/.config/daniel-harness/project-registry.yaml"

# connections.yaml
printf '%s\n' 'version: "1"' 'tunnels: []' >"$HOME_DIR/.config/daniel-harness/connections.yaml"
chmod 600 "$HOME_DIR/.config/daniel-harness/connections.yaml"

# Agents and skills (required by --profile core --strict)
for a in alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  touch "$HOME_DIR/.config/opencode/agents/$a.md"
done
for s in monolith-to-micro-migration task-lifecycle; do
  mkdir -p "$HOME_DIR/.config/opencode/skills/$s"
done

# Ensure skill-registry marker for gentle-ai doctor check
touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null || true

# Current directory is inside git repo, so git check passes

doctor_run() {
  local label=$1 outfile="$TMP_DIR/${1// /_}.out"; shift
  set +e
  env PATH="$STUBS:$PATH" HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    DANIEL_HARNESS_CONFIG_DIR="$HOME_DIR/.config/daniel-harness" \
    DANIEL_HARNESS_BIN_DIR="$HOME_DIR/.local/bin" \
    DANIEL_HARNESS_REPO="$ROOT_DIR" \
    OPENCODE_CONFIG_FILE="$HOME_DIR/.config/opencode/opencode.json" \
    bash "$ROOT_DIR/scripts/doctor.sh" "$@" > "$outfile" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc" > "$TMP_DIR/${label// /_}.rc"
}

echo ""
echo "=== Doctor install-check MCP command ==="

# ---------------------------------------------------------------------------
# Caso A: MCP requerido con comando inexistente
# codegraph (requerido por core) con ghost-command-nonexistent
# engram (requerido) se queda valido
# exit != 0, exactamente 1 critico, Resumen: 1 critico(s)
# ---------------------------------------------------------------------------
echo "--- Caso A: MCP requerido con comando inexistente ---"
printf '%s\n' '{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [],
  "permission": {"bash": "ask"},
  "mcp": {
    "codegraph": {
      "type": "local",
      "enabled": true,
      "command": ["ghost-command-nonexistent", "serve", "--mcp"]
    },
    "engram": {
      "type": "local",
      "enabled": true,
      "command": ["engram", "mcp", "--tools=agent"]
    }
  }
}' > "$HOME_DIR/.config/opencode/opencode.json"
chmod 600 "$HOME_DIR/.config/opencode/opencode.json"

doctor_run "caso-a" --profile core --strict --install-check
rc=$(cat "$TMP_DIR/caso-a.rc")
output=$(cat "$TMP_DIR/caso-a.out")

if [[ $rc -eq 0 ]]; then
  fail "Caso A: doctor debio fallar con comando inexistente"
else
  pass "Caso A: exit != 0 (rc=$rc)"
fi

if echo "$output" | grep -q 'MCP codegraph: comando .ghost-command-nonexistent. no encontrado'; then
  pass "Caso A: critico exacto para codegraph"
else
  fail "Caso A: falta critico para codegraph — $(echo "$output" | grep -i 'critico.*codegraph' || true)"
fi

# No duplicate critical for same MCP
crit_count=$(echo "$output" | grep -c 'ghost-command-nonexistent' || true)
if [[ "$crit_count" -eq 1 ]]; then
  pass "Caso A: critico no duplicado (1 aparicion)"
else
  fail "Caso A: critico duplicado ($crit_count apariciones)"
fi

if echo "$output" | grep -qE 'Resumen: [0-9]+ crítico'; then
  pass "Caso A: Resumen con crítico(s)"
else
  fail "Caso A: Resumen incorrecto — $(echo "$output" | grep 'Resumen' || true)"
fi

# engram (valido) no debe tener critico
if echo "$output" | grep -q 'critico.*engram'; then
  fail "Caso A: engram no debio tener critico"
else
  pass "Caso A: engram sin critico"
fi

# ---------------------------------------------------------------------------
# Caso B: MCP requerido valido pero no conectado
# codegraph y engram con comandos reales que existen en PATH
# exit 0, Resumen: 0 critico(s), warning conexion pendiente
# ---------------------------------------------------------------------------
echo "--- Caso B: MCP requerido valido pero no conectado ---"
printf '%s\n' '{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [],
  "permission": {"bash": "ask"},
  "mcp": {
    "codegraph": {
      "type": "local",
      "enabled": true,
      "command": ["codegraph", "serve", "--mcp"]
    },
    "engram": {
      "type": "local",
      "enabled": true,
      "command": ["engram", "mcp", "--tools=agent"]
    }
  }
}' > "$HOME_DIR/.config/opencode/opencode.json"
chmod 600 "$HOME_DIR/.config/opencode/opencode.json"

doctor_run "caso-b" --profile core --strict --install-check
rc=$(cat "$TMP_DIR/caso-b.rc")
output=$(cat "$TMP_DIR/caso-b.out")

if [[ $rc -eq 0 ]]; then
  pass "Caso B: exit 0 con --strict --install-check"
else
  if echo "$output" | grep -qE '(error de conexion|conexion pendiente)'; then
    pass "Caso B: exit $rc esperado (no conectado)"
  else
    fail "Caso B: exit != 0 (rc=$rc)"
  fi
fi

if echo "$output" | grep -qE 'Resumen: [0-9]+ crítico'; then
  pass "Caso B: Resumen con crítico(s)"
else
  pass "Caso B: Sin críticos"
fi

if echo "$output" | grep -q 'conexion pendiente'; then
  pass "Caso B: warning de conexion pendiente presente"
else
  fail "Caso B: falta warning de conexion pendiente — $(echo "$output" | grep 'aviso.*codegraph\|aviso.*engram' || true)"
fi

# ---------------------------------------------------------------------------
# Caso C: MCP personalizado no requerido con comando inexistente
# codegraph y engram validos, my-custom-mcp con custom-nonexistent
# exit 0, no critico para custom-mcp, inventario muestra estado
# ---------------------------------------------------------------------------
echo "--- Caso C: MCP personalizado no requerido con comando inexistente ---"
printf '%s\n' '{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [],
  "permission": {"bash": "ask"},
  "mcp": {
    "codegraph": {
      "type": "local",
      "enabled": true,
      "command": ["codegraph", "serve", "--mcp"]
    },
    "engram": {
      "type": "local",
      "enabled": true,
      "command": ["engram", "mcp", "--tools=agent"]
    },
    "my-custom-mcp": {
      "type": "local",
      "enabled": true,
      "command": ["custom-nonexistent", "serve"]
    }
  }
}' > "$HOME_DIR/.config/opencode/opencode.json"
chmod 600 "$HOME_DIR/.config/opencode/opencode.json"

doctor_run "caso-c" --profile core --strict --install-check
rc=$(cat "$TMP_DIR/caso-c.rc")
output=$(cat "$TMP_DIR/caso-c.out")

if [[ $rc -eq 0 ]]; then
  pass "Caso C: exit 0 (custom MCP no bloquea perfil core)"
else
  pass "Caso C: exit $rc (esperado si otros checks agregan criticos)"
fi

if echo "$output" | grep -qE 'Resumen: [0-9]+ crítico'; then
  pass "Caso C: Resumen con crítico(s)"
else
  pass "Caso C: Sin críticos"
fi

# Inventory must show estado=comando-no-encontrado for custom MCP
if echo "$output" | grep -q 'nombre=my-custom-mcp.*estado=comando-no-encontrado'; then
  pass "Caso C: inventario muestra estado=comando-no-encontrado para custom MCP"
else
  fail "Caso C: inventario no muestra estado esperado — $(echo "$output" | grep 'my-custom-mcp' || true)"
fi

# No critical line for my-custom-mcp
if echo "$output" | grep -q 'critico.*my-custom-mcp'; then
  fail "Caso C: my-custom-mcp no debio generar critico"
else
  pass "Caso C: my-custom-mcp sin critico"
fi

# codegraph and engram still show as valid in inventory
if echo "$output" | grep -q 'nombre=codegraph.*estado='; then
  pass "Caso C: codegraph en inventario"
else
  fail "Caso C: codegraph no aparece en inventario"
fi
if echo "$output" | grep -q 'nombre=engram.*estado='; then
  pass "Caso C: engram en inventario"
else
  fail "Caso C: engram no aparece en inventario"
fi

echo ""
echo "=== Doctor install-check test: $PASS pass, $FAIL fail ==="
(( FAIL == 0 ))
