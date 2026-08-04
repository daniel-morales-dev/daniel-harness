#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}
LOCAL_BIN=${DANIEL_HARNESS_BIN_DIR:-"$HOME/.local/bin"}

source "$ROOT_DIR/scripts/lib/managed-links.sh"

# Legacy cleanup: remove symlinks from old agent names
remove_legacy_managed_link() {
  local source=$1 target=$2
  if [[ -L "$target" ]] && [[ $(readlink "$target") == "$source" ]]; then
    rm "$target"
    printf 'eliminado symlink legacy: %s\n' "$target"
  fi
}
remove_legacy_managed_link "$ROOT_DIR/agents/senior-engineer.md" "$OPENCODE_CONFIG_DIR/agents/senior-engineer.md"
remove_legacy_managed_link "$ROOT_DIR/agents/test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/test-engineer.md"

remove_managed_link() {
  local source=$1
  local target=$2

  if [[ ! -L "$target" ]]; then
    printf 'conservado: %s no es un enlace administrado\n' "$target"
    return
  fi

  if [[ $(readlink "$target") != "$source" ]]; then
    printf 'conservado: %s apunta a otro destino\n' "$target"
    return
  fi

  rm "$target"
  printf 'eliminado: %s\n' "$target"
}

# Managed links desde inventario compartido (scripts/lib/managed-links.sh)
while IFS='|' read -r source_rel dest_var dest_rel; do
  remove_managed_link "$ROOT_DIR/$source_rel" "${!dest_var}/$dest_rel"
done < <(list_managed_links)

# Remove managed policy symlinks
POLICIES_DIR="$HARNESS_CONFIG_DIR/policies"
if [[ -d "$POLICIES_DIR" ]]; then
  for policy in "$POLICIES_DIR/"*.md; do
    remove_managed_link "$ROOT_DIR/policies/$(basename "$policy")" "$policy"
  done
  rmdir "$POLICIES_DIR" 2>/dev/null || true
fi
# Conservar policies.local (overrides locales)
printf 'conservado: %s/policies.local/ (overrides locales)\n' "$HARNESS_CONFIG_DIR"

printf '\nDesinstalación completada. La configuración local y los secretos se conservaron.\n'
