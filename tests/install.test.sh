#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_ROOT="$TMP_DIR/config"
HARNESS_CONFIG="$CONFIG_ROOT/daniel-harness"
OPENCODE_CONFIG="$CONFIG_ROOT/opencode"
FIRST_OUTPUT="$TMP_DIR/first.out"
SECOND_OUTPUT="$TMP_DIR/second.out"
FOREIGN_TARGET="$TMP_DIR/foreign-command.md"

HOME="$TMP_DIR/home" XDG_CONFIG_HOME="$CONFIG_ROOT" "$ROOT_DIR/scripts/install.sh" >"$FIRST_OUTPUT"

[[ -L "$OPENCODE_CONFIG/agents/senior-engineer.md" ]]
[[ -L "$OPENCODE_CONFIG/skills/monolith-to-micro-migration" ]]
[[ -L "$OPENCODE_CONFIG/commands/migration-gap-analysis.md" ]]
[[ $(stat -c '%a' "$HARNESS_CONFIG/config.yaml") == 600 ]]
[[ $(stat -c '%a' "$HARNESS_CONFIG/secrets") == 700 ]]

CONFIG_HASH=$(sha256sum "$HARNESS_CONFIG/config.yaml" | cut -d' ' -f1)
HOME="$TMP_DIR/home" XDG_CONFIG_HOME="$CONFIG_ROOT" "$ROOT_DIR/scripts/install.sh" >"$SECOND_OUTPUT"
[[ $(sha256sum "$HARNESS_CONFIG/config.yaml" | cut -d' ' -f1) == "$CONFIG_HASH" ]]
grep -F "skip: $HARNESS_CONFIG/config.yaml already exists" "$SECOND_OUTPUT" >/dev/null

rm "$OPENCODE_CONFIG/commands/migration-gap-analysis.md"
printf 'foreign synthetic command\n' >"$FOREIGN_TARGET"
ln -s "$FOREIGN_TARGET" "$OPENCODE_CONFIG/commands/migration-gap-analysis.md"

HOME="$TMP_DIR/home" XDG_CONFIG_HOME="$CONFIG_ROOT" "$ROOT_DIR/scripts/uninstall.sh" >/dev/null

[[ ! -L "$OPENCODE_CONFIG/agents/senior-engineer.md" ]]
[[ ! -L "$OPENCODE_CONFIG/skills/monolith-to-micro-migration" ]]
[[ -L "$OPENCODE_CONFIG/commands/migration-gap-analysis.md" ]]
[[ $(readlink "$OPENCODE_CONFIG/commands/migration-gap-analysis.md") == "$FOREIGN_TARGET" ]]
[[ -f "$HARNESS_CONFIG/config.yaml" ]]
[[ -d "$HARNESS_CONFIG/secrets" ]]

printf 'install/uninstall tests passed\n'
