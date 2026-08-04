#!/usr/bin/env bash
# tests/install-symmetry.test.sh
# Verifica que install.sh y uninstall.sh sean simétricos
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_DIR="$TMP_DIR/home"
mkdir -p "$HOME_DIR/.local/bin"

export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export OPENCODE_CONFIG_DIR="$HOME_DIR/.config/opencode"
export DANIEL_HARNESS_CONFIG_DIR="$HOME_DIR/.config/daniel-harness"
export DANIEL_HARNESS_BIN_DIR="$HOME_DIR/.local/bin"
export PATH="$HOME_DIR/.local/bin:$PATH"

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "=== Fase 1: install crea todos los enlaces ==="

bash "$ROOT_DIR/scripts/install.sh" > "$TMP_DIR/install.out" 2>&1
INSTALL_RC=$?
echo "install.sh exit code: $INSTALL_RC"

source "$ROOT_DIR/scripts/lib/managed-links.sh"

# Las variables usadas por el inventario deben estar definidas
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME_DIR/.config/opencode}"
LOCAL_BIN="${DANIEL_HARNESS_BIN_DIR:-$HOME_DIR/.local/bin}"
HARNESS_CONFIG_DIR="${DANIEL_HARNESS_CONFIG_DIR:-$HOME_DIR/.config/daniel-harness}"

MISSING=0
while IFS='|' read -r source_rel dest_var dest_rel; do
  target="${!dest_var}/$dest_rel"
  if [[ -f "$target" || -L "$target" || -d "$target" ]]; then
    pass "enlace creado: $dest_rel"
  else
    fail "enlace faltante: $dest_rel"
    MISSING=$((MISSING + 1))
  fi
done < <(list_managed_links)

# Policies también deben estar
for policy in "$ROOT_DIR/policies/"*.md; do
  pname=$(basename "$policy")
  target="$DANIEL_HARNESS_CONFIG_DIR/policies/$pname"
  if [[ -f "$target" || -L "$target" ]]; then
    pass "policy enlazada: $pname"
  else
    fail "policy faltante: $pname"
  fi
done

echo "=== Fase 2: uninstall elimina todos los enlaces administrados ==="

# Marcamos personal files antes de uninstall
echo "custom content" > "$DANIEL_HARNESS_CONFIG_DIR/custom-config.yaml"
mkdir -p "$DANIEL_HARNESS_CONFIG_DIR/policies.local"
echo "custom override" > "$DANIEL_HARNESS_CONFIG_DIR/policies.local/override.md"

bash "$ROOT_DIR/scripts/uninstall.sh" > "$TMP_DIR/uninstall.out" 2>&1
UNINSTALL_RC=$?
echo "uninstall.sh exit code: $UNINSTALL_RC"

# Verificar que enlaces administrados desaparecieron
while IFS='|' read -r source_rel dest_var dest_rel; do
  target="${!dest_var}/$dest_rel"
  if [[ -e "$target" || -L "$target" ]]; then
    fail "enlace NO eliminado: $dest_rel"
  else
    pass "enlace eliminado: $dest_rel"
  fi
done < <(list_managed_links)

echo "=== Fase 3: archivos personalizados conservados ==="

if [[ -f "$DANIEL_HARNESS_CONFIG_DIR/custom-config.yaml" ]]; then
  pass "custom-config.yaml conservado"
else
  fail "custom-config.yaml eliminado"
fi

if [[ -d "$DANIEL_HARNESS_CONFIG_DIR/policies.local" ]]; then
  pass "policies.local conservado"
else
  fail "policies.local eliminado"
fi

if [[ -f "$DANIEL_HARNESS_CONFIG_DIR/policies.local/override.md" ]]; then
  pass "override.md en policies.local conservado"
else
  fail "override.md en policies.local eliminado"
fi

echo "=== Fase 4: configuracion local conservada ==="

if [[ -f "$DANIEL_HARNESS_CONFIG_DIR/config.yaml" ]]; then
  pass "config.yaml conservado"
else
  fail "config.yaml eliminado"
fi

if [[ -f "$DANIEL_HARNESS_CONFIG_DIR/connections.yaml" ]]; then
  pass "connections.yaml conservado"
else
  fail "connections.yaml eliminado"
fi

if [[ -d "$DANIEL_HARNESS_CONFIG_DIR/secrets" ]]; then
  pass "secrets/ conservado"
else
  fail "secrets/ eliminado"
fi

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
