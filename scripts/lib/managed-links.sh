# scripts/lib/managed-links.sh
# Inventario único de recursos administrados — consumido por install.sh y uninstall.sh
# Formato: source_rel_path|dest_var|dest_rel_path
#   source_rel_path: relativo a ROOT_DIR
#   dest_var: nombre de variable de entorno (OPENCODE_CONFIG_DIR, LOCAL_BIN, ...)
#   dest_rel_path: relativo al directorio base
list_managed_links() {
  cat <<'LINKS'
agents/alegra-microservice-engineer.md|OPENCODE_CONFIG_DIR|agents/alegra-microservice-engineer.md
agents/code-reviewer.md|OPENCODE_CONFIG_DIR|agents/code-reviewer.md
agents/alegra-microservice-test-engineer.md|OPENCODE_CONFIG_DIR|agents/alegra-microservice-test-engineer.md
agents/php-engineer.md|OPENCODE_CONFIG_DIR|agents/php-engineer.md
agents/migration-parity-reviewer.md|OPENCODE_CONFIG_DIR|agents/migration-parity-reviewer.md
skills/monolith-to-micro-migration|OPENCODE_CONFIG_DIR|skills/monolith-to-micro-migration
skills/task-lifecycle|OPENCODE_CONFIG_DIR|skills/task-lifecycle
commands/migration-gap-analysis.md|OPENCODE_CONFIG_DIR|commands/migration-gap-analysis.md
commands/mysql-query.md|OPENCODE_CONFIG_DIR|commands/mysql-query.md
commands/mongodb-query.md|OPENCODE_CONFIG_DIR|commands/mongodb-query.md
commands/dynamodb-read.md|OPENCODE_CONFIG_DIR|commands/dynamodb-read.md
commands/dynamodb-write-confirmed.md|OPENCODE_CONFIG_DIR|commands/dynamodb-write-confirmed.md
commands/object-storage-read.md|OPENCODE_CONFIG_DIR|commands/object-storage-read.md
bin/dh|LOCAL_BIN|dh
install|LOCAL_BIN|dh-install
global/AGENTS.md|OPENCODE_CONFIG_DIR|AGENTS.md
LINKS
}
