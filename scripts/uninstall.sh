#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}

remove_managed_link() {
  local source=$1
  local target=$2

  if [[ ! -L "$target" ]]; then
    printf 'preserved: %s is not a managed link\n' "$target"
    return
  fi

  if [[ $(readlink "$target") != "$source" ]]; then
    printf 'preserved: %s points elsewhere\n' "$target"
    return
  fi

  rm "$target"
  printf 'removed: %s\n' "$target"
}

remove_managed_link "$ROOT_DIR/agents/senior-engineer.md" "$OPENCODE_CONFIG_DIR/agents/senior-engineer.md"
remove_managed_link "$ROOT_DIR/agents/code-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/code-reviewer.md"
remove_managed_link "$ROOT_DIR/agents/test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/test-engineer.md"
remove_managed_link "$ROOT_DIR/skills/monolith-to-micro-migration" "$OPENCODE_CONFIG_DIR/skills/monolith-to-micro-migration"
remove_managed_link "$ROOT_DIR/commands/migration-gap-analysis.md" "$OPENCODE_CONFIG_DIR/commands/migration-gap-analysis.md"

printf '\nUninstall complete. Local Daniel Harness configuration and secrets were preserved.\n'
