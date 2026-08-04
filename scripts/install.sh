#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}
LOCAL_BIN=${DANIEL_HARNESS_BIN_DIR:-"$HOME/.local/bin"}
EXPERIMENTAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --experimental-data-tools) EXPERIMENTAL=true; shift ;;
    *) printf 'Argumento desconocido: %s\n' "$1" >&2; exit 1 ;;
  esac
done

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

install_config_if_missing() {
  local source=$1
  local target=$2

  if [[ -e "$target" ]]; then
    printf 'omitido: %s ya existe\n' "$target"
    return
  fi

  install -m 600 "$source" "$target"
  printf 'instalado: %s\n' "$target"
}

link_if_missing() {
  local source=$1
  local target=$2

  if [[ ! -e "$source" ]]; then
    printf 'error: la fuente administrada no existe: %s\n' "$source" >&2
    return 1
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    printf 'omitido: %s ya existe\n' "$target"
    return
  fi

  ln -s "$source" "$target"
  printf 'enlazado: %s -> %s\n' "$target" "$source"
}

install -d -m 700 "$HARNESS_CONFIG_DIR"
install -d -m 700 \
  "$HARNESS_CONFIG_DIR/secrets" \
  "$HARNESS_CONFIG_DIR/secrets/mysql" \
  "$HARNESS_CONFIG_DIR/secrets/mongodb" \
  "$HARNESS_CONFIG_DIR/secrets/tunnels" \
  "$HARNESS_CONFIG_DIR/secrets/tokens"

install_config_if_missing "$ROOT_DIR/examples/config.example.yaml" "$HARNESS_CONFIG_DIR/config.yaml"
install_config_if_missing "$ROOT_DIR/examples/connections.example.yaml" "$HARNESS_CONFIG_DIR/connections.yaml"
install_config_if_missing "$ROOT_DIR/examples/project-registry.example.yaml" "$HARNESS_CONFIG_DIR/project-registry.yaml"

install -d -m 700 "$OPENCODE_CONFIG_DIR/agents" "$OPENCODE_CONFIG_DIR/skills" "$OPENCODE_CONFIG_DIR/commands" "$OPENCODE_CONFIG_DIR/tools"

install -d -m 700 "$HARNESS_CONFIG_DIR/policies" "$HARNESS_CONFIG_DIR/policies.local"
for policy in "$ROOT_DIR/policies/"*.md; do
  link_if_missing "$policy" "$HARNESS_CONFIG_DIR/policies/$(basename "$policy")"
done

# Managed links desde inventario compartido
install -d -m 700 "$LOCAL_BIN"
while IFS='|' read -r source_rel dest_var dest_rel; do
  dest_dir=$(dirname "${!dest_var}/$dest_rel")
  [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
  link_if_missing "$ROOT_DIR/$source_rel" "${!dest_var}/$dest_rel"
done < <(list_managed_links)

# Recursos experimentales (closed data tools)
if $EXPERIMENTAL; then
  printf '\n[aviso] Instalando closed data tools experimentales (beta)\n'
  printf '  Estas herramientas no son estables en v0.1.0.\n'
  printf '  Reporta errores en https://github.com/daniel-morales-dev/daniel-harness/issues\n\n'
  while IFS='|' read -r source_rel dest_var dest_rel; do
    dest_dir=$(dirname "${!dest_var}/$dest_rel")
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
    link_if_missing "$ROOT_DIR/$source_rel" "${!dest_var}/$dest_rel"
  done < <(list_experimental_links)
fi

printf '\nInstalación completada. Ejecuta dh doctor para verificar.\n'
