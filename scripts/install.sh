#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}
LOCAL_BIN=${DANIEL_HARNESS_BIN_DIR:-"$HOME/.local/bin"}

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

  # -L también protege enlaces rotos, que -e no detecta.
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

install -d -m 700 "$OPENCODE_CONFIG_DIR/agents" "$OPENCODE_CONFIG_DIR/skills" "$OPENCODE_CONFIG_DIR/commands"

install -d -m 700 "$HARNESS_CONFIG_DIR/policies"
for policy in "$ROOT_DIR/policies/"*.md; do
  install_config_if_missing "$policy" "$HARNESS_CONFIG_DIR/policies/$(basename "$policy")"
done

link_if_missing "$ROOT_DIR/global/AGENTS.md" "$OPENCODE_CONFIG_DIR/AGENTS.md"

link_if_missing "$ROOT_DIR/agents/alegra-microservice-engineer.md" "$OPENCODE_CONFIG_DIR/agents/alegra-microservice-engineer.md"
link_if_missing "$ROOT_DIR/agents/code-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/code-reviewer.md"
link_if_missing "$ROOT_DIR/agents/alegra-microservice-test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/alegra-microservice-test-engineer.md"
link_if_missing "$ROOT_DIR/agents/php-engineer.md" "$OPENCODE_CONFIG_DIR/agents/php-engineer.md"
link_if_missing "$ROOT_DIR/agents/migration-parity-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/migration-parity-reviewer.md"
link_if_missing "$ROOT_DIR/skills/monolith-to-micro-migration" "$OPENCODE_CONFIG_DIR/skills/monolith-to-micro-migration"
link_if_missing "$ROOT_DIR/skills/task-lifecycle" "$OPENCODE_CONFIG_DIR/skills/task-lifecycle"
link_if_missing "$ROOT_DIR/commands/migration-gap-analysis.md" "$OPENCODE_CONFIG_DIR/commands/migration-gap-analysis.md"

install -d -m 700 "$LOCAL_BIN"
link_if_missing "$ROOT_DIR/bin/dh" "$LOCAL_BIN/dh"
link_if_missing "$ROOT_DIR/install" "$LOCAL_BIN/dh-install"

printf '\nInstalación completada. Ejecuta dh doctor para verificar.\n'
