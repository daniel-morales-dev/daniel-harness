#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}

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

remove_managed_link "$ROOT_DIR/agents/alegra-microservice-engineer.md" "$OPENCODE_CONFIG_DIR/agents/alegra-microservice-engineer.md"
remove_managed_link "$ROOT_DIR/agents/code-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/code-reviewer.md"
remove_managed_link "$ROOT_DIR/agents/alegra-microservice-test-engineer.md" "$OPENCODE_CONFIG_DIR/agents/alegra-microservice-test-engineer.md"
remove_managed_link "$ROOT_DIR/agents/php-engineer.md" "$OPENCODE_CONFIG_DIR/agents/php-engineer.md"
remove_managed_link "$ROOT_DIR/agents/migration-parity-reviewer.md" "$OPENCODE_CONFIG_DIR/agents/migration-parity-reviewer.md"
remove_managed_link "$ROOT_DIR/skills/monolith-to-micro-migration" "$OPENCODE_CONFIG_DIR/skills/monolith-to-micro-migration"
remove_managed_link "$ROOT_DIR/skills/task-lifecycle" "$OPENCODE_CONFIG_DIR/skills/task-lifecycle"
remove_managed_link "$ROOT_DIR/commands/migration-gap-analysis.md" "$OPENCODE_CONFIG_DIR/commands/migration-gap-analysis.md"
remove_managed_link "$ROOT_DIR/bin/dh" "$HOME/.local/bin/dh"
remove_managed_link "$ROOT_DIR/global/AGENTS.md" "$OPENCODE_CONFIG_DIR/AGENTS.md"

# Remove managed policies directory (only if it matches harness policies)
POLICIES_DIR="$HARNESS_CONFIG_DIR/policies"
if [[ -d "$POLICIES_DIR" ]]; then
  all_managed=true
  for policy in "$POLICIES_DIR/"*.md; do
    [[ -f "$policy" ]] || continue
    src="$ROOT_DIR/policies/$(basename "$policy")"
    if [[ -f "$src" ]] && diff -q "$policy" "$src" >/dev/null 2>&1; then
      rm "$policy"
      printf 'eliminado: %s\n' "$policy"
    else
      printf 'conservado: %s (modificado localmente)\n' "$policy"
      all_managed=false
    fi
  done
  if [[ "$all_managed" == true ]]; then
    rmdir "$POLICIES_DIR" 2>/dev/null || true
  fi
fi

printf '\nDesinstalación completada. La configuración local y los secretos se conservaron.\n'
