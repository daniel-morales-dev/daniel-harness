#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}

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

remove_managed_link "$ROOT_DIR/agents/senior-engineer.md" "$OPENCODE_CONFIG_DIR/agents/senior-engineer.md"
remove_managed_link "$ROOT_DIR/agents/code-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/code-reviewer.md"
remove_managed_link "$ROOT_DIR/agents/test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/test-engineer.md"
remove_managed_link "$ROOT_DIR/agents/php-engineer.md" "$OPENCODE_CONFIG_DIR/agents/php-engineer.md"
remove_managed_link "$ROOT_DIR/skills/monolith-to-micro-migration" "$OPENCODE_CONFIG_DIR/skills/monolith-to-micro-migration"
remove_managed_link "$ROOT_DIR/skills/task-lifecycle" "$OPENCODE_CONFIG_DIR/skills/task-lifecycle"
remove_managed_link "$ROOT_DIR/commands/migration-gap-analysis.md" "$OPENCODE_CONFIG_DIR/commands/migration-gap-analysis.md"
remove_managed_link "$ROOT_DIR/bin/dh" "$HOME/.local/bin/dh"

printf '\nDesinstalación completada. La configuración local y los secretos se conservaron.\n'
