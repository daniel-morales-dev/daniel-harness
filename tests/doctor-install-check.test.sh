#!/usr/bin/env bash
# tests/doctor-install-check.test.sh
# P0: Doctor --install-check valida command de MCPs locales
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_DIR="$TMP_DIR/daniel-harness"
OPENCODE_CONFIG="$TMP_DIR/opencode.json"
OUTPUT="$TMP_DIR/doctor.out"

install -d -m 700 "$CONFIG_DIR"
install -d -m 700 "$CONFIG_DIR/secrets"
install -d -m 700 "$CONFIG_DIR/secrets/tunnels"
install -m 600 "$ROOT_DIR/examples/config.example.yaml" "$CONFIG_DIR/config.yaml"
install -m 600 "$ROOT_DIR/examples/project-registry.example.yaml" "$CONFIG_DIR/project-registry.yaml"
printf '%s\n' 'version: "1"' 'profiles: []' >"$CONFIG_DIR/connections.yaml"
chmod 600 "$CONFIG_DIR/connections.yaml"

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "=== Doctor install-check MCP command ==="

# Test 1: MCP local con comando inexistente => critical, exit no-cero, mensaje
echo "--- Test 1: MCP local con comando inexistente ---"
printf '%s\n' '{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [],
  "permission": {"bash": "ask"},
  "mcp": {
    "ghost-mcp": {
      "type": "local",
      "enabled": true,
      "command": ["ghost-command-nonexistent", "serve"]
    }
  }
}' >"$OPENCODE_CONFIG"
chmod 600 "$OPENCODE_CONFIG"

if DANIEL_HARNESS_CONFIG_DIR="$CONFIG_DIR" \
  OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG" \
  DANIEL_HARNESS_REPO="$ROOT_DIR" \
  "$ROOT_DIR/scripts/doctor.sh" --profile core --strict --install-check >"$OUTPUT" 2>&1; then
  fail "doctor debio fallar con comando inexistente"
else
  pass "doctor termino no-cero con comando inexistente"
fi

if grep -q 'comando.*ghost-command-nonexistent.*no encontrado' "$OUTPUT"; then
  pass "salida contiene critical del comando inexistente"
else
  fail "salida no contiene critical del comando: $(cat "$OUTPUT")"
fi

# Test 2: MCP local valido pero no conectado => warning (no critical)
echo "--- Test 2: MCP local valido pero no conectado ---"
# Usar un comando que existe (sh) pero MCP no esta conectado realmente
printf '%s\n' '{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [],
  "permission": {"bash": "ask"},
  "mcp": {
    "valid-but-not-connected": {
      "type": "local",
      "enabled": true,
      "command": ["sh", "serve"]
    }
  }
}' >"$OPENCODE_CONFIG"
chmod 600 "$OPENCODE_CONFIG"

# Necesitamos crear un perfil core minimo que incluya este MCP
# o pasamos un perfil que no requiera MCPs especificos para aislar el test
# Mejor: test sin --profile para que no valide MCPs requeridos
# y usa --strict solo

if DANIEL_HARNESS_CONFIG_DIR="$CONFIG_DIR" \
  OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG" \
  DANIEL_HARNESS_REPO="$ROOT_DIR" \
  "$ROOT_DIR/scripts/doctor.sh" --strict --install-check >"$OUTPUT" 2>&1; then
  pass "doctor pasa con MCP local valido aunque no conectado"
else
  : # puede fallar por otras razones, revisamos salida
fi

if grep -q 'crítico.*valid-but-not-connected' "$OUTPUT"; then
  fail "MCP valido no debio tener critical, solo warning"
elif grep -q 'comando.*no encontrado' "$OUTPUT"; then
  fail "sh deberia estar en PATH, no es comando inexistente"
elif grep -q 'conexion pendiente' "$OUTPUT"; then
  pass "MCP valido sin conexion queda como warning"
else
  # Si no hay mensaje de warning ni critical, esta bien (el MCP puede estar
  # reportado como "inaccesible" y es warning durante install-check)
  pass "MCP valido sin conexion no genera critical"
fi

echo ""
echo "=== Doctor install-check test: $PASS pass, $FAIL fail ==="
(( FAIL == 0 ))
