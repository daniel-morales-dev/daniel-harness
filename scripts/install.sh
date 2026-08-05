#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}
LOCAL_BIN=${DANIEL_HARNESS_BIN_DIR:-"$HOME/.local/bin"}
EXPERIMENTAL=false
RESET_MANAGED=false
SKIP_RESOURCES=false
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --experimental-data-tools) EXPERIMENTAL=true; shift ;;
    --reset-managed) RESET_MANAGED=true; shift ;;
    --skip-resources) SKIP_RESOURCES=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    *) printf 'Argumento desconocido: %s\n' "$1" >&2; exit 1 ;;
  esac
done

source "$ROOT_DIR/scripts/lib/managed-links.sh"

# --- version ---
HARNESS_VERSION=$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "unknown")

# --- managed state file (flat, grep/awk friendly) ---
# Format: logical_path|harness_version|source_hash|installed_hash|date|owner
MANAGED_STATE_FILE="$HARNESS_CONFIG_DIR/state/opencode-managed.state"

_get_managed_state() {
  local logical=$1
  [[ -f "$MANAGED_STATE_FILE" ]] || return 1
  grep "^${logical}|" "$MANAGED_STATE_FILE" 2>/dev/null || true
}

_record_managed_state() {
  local logical=$1 source_hash=$2 installed_hash=$3
  local date_line
  date_line=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local state_dir
  state_dir=$(dirname "$MANAGED_STATE_FILE")
  install -d -m 700 "$state_dir"

  if [[ ! -f "$MANAGED_STATE_FILE" ]]; then
    {
      printf '# Managed by daniel-harness install.sh\n'
      printf 'version=%s\n' "$HARNESS_VERSION"
      printf '# logical_path|harness_version|source_hash|installed_hash|date|owner\n'
      printf '%s|%s|%s|%s|%s|harness\n' "$logical" "$HARNESS_VERSION" "$source_hash" "$installed_hash" "$date_line"
    } > "$MANAGED_STATE_FILE"
    chmod 600 "$MANAGED_STATE_FILE"
    return
  fi

  # Update version line
  sed -i "s/^version=.*/version=$HARNESS_VERSION/" "$MANAGED_STATE_FILE"

  # Upsert resource entry
  if grep -q "^${logical}|" "$MANAGED_STATE_FILE" 2>/dev/null; then
    sed -i "s#^${logical}|.*#${logical}|${HARNESS_VERSION}|${source_hash}|${installed_hash}|${date_line}|harness#" "$MANAGED_STATE_FILE"
  else
    printf '%s|%s|%s|%s|%s|harness\n' "$logical" "$HARNESS_VERSION" "$source_hash" "$installed_hash" "$date_line" >> "$MANAGED_STATE_FILE"
  fi
}

# --- helpers ---

_is_harness_owned_symlink() {
  local target=$1
  [[ "$target" == "$ROOT_DIR"* ]] && return 0
  [[ "$target" == "$HOME/.local/share/daniel-harness"* ]] && return 0
  # Check managed state for known old checkout paths
  local state_line
  state_line=$(_get_managed_state "agent-path:$target" 2>/dev/null || true)
  [[ -n "$state_line" ]] && return 0
  return 1
}

remove_legacy_managed_link() {
  local source=$1 target=$2
  if [[ -L "$target" ]] && [[ $(readlink "$target") == "$source" ]]; then
    rm "$target"
    printf 'eliminado symlink legacy: %s\n' "$target"
  fi
}

install_config_if_missing() {
  local source=$1 target=$2
  if [[ -e "$target" ]]; then
    printf 'omitido: %s ya existe\n' "$target"
    return
  fi
  install -m 600 "$source" "$target"
  printf 'instalado: %s\n' "$target"
}

link_if_missing() {
  local source=$1 target=$2
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

# --- managed copy install ---

install_managed_copy() {
  local source=$1 target=$2 logical=$3
  local source_hash current_hash state_line expected_hash

  [[ -f "$source" ]] || { printf 'error: fuente no existe: %s\n' "$source" >&2; return 1; }
  source_hash=$(sha256sum "$source" | cut -d' ' -f1)

  # Target does not exist — fresh install
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    install -m 600 "$source" "$target"
    _record_managed_state "$logical" "$source_hash" "$source_hash"
    printf 'instalado: %s\n' "$target"
    return
  fi

  # Target is a symlink
  if [[ -L "$target" ]]; then
    local link_target
    link_target=$(readlink "$target")
    if _is_harness_owned_symlink "$link_target"; then
      rm "$target"
      install -m 600 "$source" "$target"
      _record_managed_state "$logical" "$source_hash" "$source_hash"
      printf 'reemplazado symlink por copia: %s\n' "$target"
    else
      printf 'conflicto: %s es symlink de terceros -> %s\n' "$target" "$link_target"
    fi
    return
  fi

  # Regular file exists — check state
  state_line=$(_get_managed_state "$logical")

  if [[ -z "$state_line" ]]; then
    # No managed state — adopt if content matches, skip otherwise
    current_hash=$(sha256sum "$target" | cut -d' ' -f1)
    if [[ "$current_hash" == "$source_hash" ]]; then
      _record_managed_state "$logical" "$source_hash" "$source_hash"
      printf 'adoptado: %s (contenido coincide)\n' "$target"
    elif $RESET_MANAGED; then
      printf 'conflicto: %s no tiene estado gestionado, no se sobreescribe (--reset-managed no fuerza)\n' "$target"
    else
      printf 'omitido: %s es propiedad del usuario (sin estado gestionado)\n' "$target"
    fi
    return
  fi

  expected_hash=$(echo "$state_line" | cut -d'|' -f4)

  if $RESET_MANAGED; then
    install -m 600 "$source" "$target"
    _record_managed_state "$logical" "$source_hash" "$source_hash"
    printf 'reinstalado (--reset-managed): %s\n' "$target"
    return
  fi

  current_hash=$(sha256sum "$target" | cut -d' ' -f1)

  if [[ "$current_hash" == "$expected_hash" ]]; then
    # File is as we left it — update to latest source
    install -m 600 "$source" "$target"
    _record_managed_state "$logical" "$source_hash" "$source_hash"
    printf 'actualizado: %s\n' "$target"
  else
    printf 'conflicto: %s fue modificado por el usuario, conservado\n' "$target"
    if [[ ${NON_INTERACTIVE:-false} == true ]]; then
      return 1
    fi
  fi
}

# ====== MAIN ======

# Legacy agent symlink cleanup (old names)
remove_legacy_managed_link "$ROOT_DIR/agents/senior-engineer.md" "$OPENCODE_CONFIG_DIR/agents/senior-engineer.md"
remove_legacy_managed_link "$ROOT_DIR/agents/test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/test-engineer.md"

# Harness config dir + secrets
install -d -m 700 "$HARNESS_CONFIG_DIR"
install -d -m 700 \
  "$HARNESS_CONFIG_DIR/secrets" \
  "$HARNESS_CONFIG_DIR/secrets/mysql" \
  "$HARNESS_CONFIG_DIR/secrets/mongodb" \
  "$HARNESS_CONFIG_DIR/secrets/tunnels" \
  "$HARNESS_CONFIG_DIR/secrets/tokens" \
  "$HARNESS_CONFIG_DIR/secrets/github" \
  "$HARNESS_CONFIG_DIR/secrets/navi"

# Example configs
install_config_if_missing "$ROOT_DIR/examples/config.example.yaml" "$HARNESS_CONFIG_DIR/config.yaml"
install_config_if_missing "$ROOT_DIR/examples/connections.example.yaml" "$HARNESS_CONFIG_DIR/connections.yaml"
install_config_if_missing "$ROOT_DIR/examples/project-registry.example.yaml" "$HARNESS_CONFIG_DIR/project-registry.yaml"

# Agent/skill/command/tool dirs
install -d -m 700 "$OPENCODE_CONFIG_DIR/agents" "$OPENCODE_CONFIG_DIR/skills" "$OPENCODE_CONFIG_DIR/commands" "$OPENCODE_CONFIG_DIR/tools"

# Policy links
install -d -m 700 "$HARNESS_CONFIG_DIR/policies" "$HARNESS_CONFIG_DIR/policies.local"
for policy in "$ROOT_DIR/policies/"*.md; do
  link_if_missing "$policy" "$HARNESS_CONFIG_DIR/policies/$(basename "$policy")"
done

# Managed COPIES — 5 agents via list_managed_files (installed as regular files with state tracking)
while IFS='|' read -r source_rel dest_var dest_rel; do
  install_managed_copy "$ROOT_DIR/$source_rel" "${!dest_var}/$dest_rel" "$source_rel"
done < <(list_managed_files)

# Resources (symlinks via list_managed_links + list_experimental_links) — skipped with --skip-resources
if ! $SKIP_RESOURCES; then
  install -d -m 700 "$LOCAL_BIN"
  while IFS='|' read -r source_rel dest_var dest_rel; do
    dest_dir=$(dirname "${!dest_var}/$dest_rel")
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
    link_if_missing "$ROOT_DIR/$source_rel" "${!dest_var}/$dest_rel"
  done < <(list_managed_links)

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
fi

printf '\nInstalacion completada. Ejecuta dh doctor para verificar.\n'
