#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}

install_config_if_missing() {
  local source=$1
  local target=$2

  if [[ -e "$target" ]]; then
    printf 'skip: %s already exists\n' "$target"
    return
  fi

  install -m 600 "$source" "$target"
  printf 'installed: %s\n' "$target"
}

link_if_missing() {
  local source=$1
  local target=$2

  if [[ -e "$target" || -L "$target" ]]; then
    printf 'skip: %s already exists\n' "$target"
    return
  fi

  ln -s "$source" "$target"
  printf 'linked: %s -> %s\n' "$target" "$source"
}

install -d -m 700 "$HARNESS_CONFIG_DIR"
install -d -m 700 \
  "$HARNESS_CONFIG_DIR/secrets" \
  "$HARNESS_CONFIG_DIR/secrets/mysql" \
  "$HARNESS_CONFIG_DIR/secrets/mongodb" \
  "$HARNESS_CONFIG_DIR/secrets/tokens"

install_config_if_missing "$ROOT_DIR/examples/config.example.yaml" "$HARNESS_CONFIG_DIR/config.yaml"
install_config_if_missing "$ROOT_DIR/examples/connections.example.yaml" "$HARNESS_CONFIG_DIR/connections.yaml"
install_config_if_missing "$ROOT_DIR/examples/project-registry.example.yaml" "$HARNESS_CONFIG_DIR/project-registry.yaml"

install -d -m 700 "$OPENCODE_CONFIG_DIR/agents" "$OPENCODE_CONFIG_DIR/skills" "$OPENCODE_CONFIG_DIR/commands"

link_if_missing "$ROOT_DIR/agents/senior-engineer.md" "$OPENCODE_CONFIG_DIR/agents/senior-engineer.md"
link_if_missing "$ROOT_DIR/agents/code-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/code-reviewer.md"
link_if_missing "$ROOT_DIR/agents/test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/test-engineer.md"
link_if_missing "$ROOT_DIR/skills/monolith-to-micro-migration" "$OPENCODE_CONFIG_DIR/skills/monolith-to-micro-migration"
link_if_missing "$ROOT_DIR/commands/migration-gap-analysis.md" "$OPENCODE_CONFIG_DIR/commands/migration-gap-analysis.md"

printf '\nInstallation complete. Restart OpenCode to load new assets.\n'
