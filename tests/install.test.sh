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

[[ -L "$OPENCODE_CONFIG/agents/alegra-microservice-engineer.md" ]]
[[ -e "$OPENCODE_CONFIG/agents/alegra-microservice-engineer.md" ]]
[[ -L "$OPENCODE_CONFIG/agents/code-reviewer.md" ]]
[[ -e "$OPENCODE_CONFIG/agents/code-reviewer.md" ]]
[[ -L "$OPENCODE_CONFIG/agents/alegra-microservice-test-engineer.md" ]]
[[ -e "$OPENCODE_CONFIG/agents/alegra-microservice-test-engineer.md" ]]
[[ -L "$OPENCODE_CONFIG/agents/php-engineer.md" ]]
[[ -e "$OPENCODE_CONFIG/agents/php-engineer.md" ]]
[[ -L "$OPENCODE_CONFIG/agents/migration-parity-reviewer.md" ]]
[[ -e "$OPENCODE_CONFIG/agents/migration-parity-reviewer.md" ]]
[[ -L "$OPENCODE_CONFIG/skills/monolith-to-micro-migration" ]]
[[ -L "$OPENCODE_CONFIG/skills/task-lifecycle" ]]
[[ -L "$OPENCODE_CONFIG/commands/migration-gap-analysis.md" ]]
[[ -L "$TMP_DIR/home/.local/bin/dh" ]]
[[ -e "$TMP_DIR/home/.local/bin/dh" ]]
# Verificar que data tools commands NO se instalaron por defecto (experimental)
[[ ! -L "$OPENCODE_CONFIG/commands/mysql-query.md" ]]
[[ ! -L "$OPENCODE_CONFIG/commands/mongodb-query.md" ]]
[[ ! -L "$OPENCODE_CONFIG/commands/dynamodb-read.md" ]]
[[ ! -L "$OPENCODE_CONFIG/commands/dynamodb-write-confirmed.md" ]]
[[ ! -L "$OPENCODE_CONFIG/commands/object-storage-read.md" ]]
[[ ! -L "$OPENCODE_CONFIG/agents/data-access.md" ]]
[[ ! -L "$TMP_DIR/home/.local/bin/dh-data-executor" ]]
[[ $(stat -c '%a' "$HARNESS_CONFIG/config.yaml") == 600 ]]
[[ $(stat -c '%a' "$HARNESS_CONFIG/secrets") == 700 ]]
[[ $(stat -c '%a' "$HARNESS_CONFIG/secrets/tunnels") == 700 ]]

CONFIG_HASH=$(sha256sum "$HARNESS_CONFIG/config.yaml" | cut -d' ' -f1)
HOME="$TMP_DIR/home" XDG_CONFIG_HOME="$CONFIG_ROOT" "$ROOT_DIR/scripts/install.sh" >"$SECOND_OUTPUT"
[[ $(sha256sum "$HARNESS_CONFIG/config.yaml" | cut -d' ' -f1) == "$CONFIG_HASH" ]]
grep -F "omitido: $HARNESS_CONFIG/config.yaml ya existe" "$SECOND_OUTPUT" >/dev/null

rm "$OPENCODE_CONFIG/commands/migration-gap-analysis.md"
printf 'foreign synthetic command\n' >"$FOREIGN_TARGET"
ln -s "$FOREIGN_TARGET" "$OPENCODE_CONFIG/commands/migration-gap-analysis.md"

HOME="$TMP_DIR/home" XDG_CONFIG_HOME="$CONFIG_ROOT" "$ROOT_DIR/scripts/uninstall.sh" >/dev/null

[[ ! -L "$OPENCODE_CONFIG/agents/alegra-microservice-engineer.md" ]]
[[ ! -L "$OPENCODE_CONFIG/agents/php-engineer.md" ]]
[[ ! -L "$OPENCODE_CONFIG/agents/migration-parity-reviewer.md" ]]
[[ ! -L "$OPENCODE_CONFIG/skills/monolith-to-micro-migration" ]]
[[ ! -L "$OPENCODE_CONFIG/skills/task-lifecycle" ]]
[[ -L "$OPENCODE_CONFIG/commands/migration-gap-analysis.md" ]]
[[ $(readlink "$OPENCODE_CONFIG/commands/migration-gap-analysis.md") == "$FOREIGN_TARGET" ]]
[[ ! -L "$TMP_DIR/home/.local/bin/dh" ]]
[[ -f "$HARNESS_CONFIG/config.yaml" ]]
[[ -d "$HARNESS_CONFIG/secrets" ]]

printf 'install/uninstall tests passed\n'
