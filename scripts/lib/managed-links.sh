# scripts/lib/managed-links.sh
# Inventario único de recursos administrados — consumido por install.sh y uninstall.sh
# Formato: source_rel_path|dest_var|dest_rel_path
#   source_rel_path: relativo a ROOT_DIR
#   dest_var: nombre de variable de entorno (OPENCODE_CONFIG_DIR, LOCAL_BIN, ...)
#   dest_rel_path: relativo al directorio base

# Recursos estables — instalados siempre
list_managed_links() {
  cat <<'LINKS'
agents/alegra-microservice-engineer.md|OPENCODE_CONFIG_DIR|agents/alegra-microservice-engineer.md
agents/alegra-microservice-test-engineer.md|OPENCODE_CONFIG_DIR|agents/alegra-microservice-test-engineer.md
agents/php-engineer.md|OPENCODE_CONFIG_DIR|agents/php-engineer.md
agents/migration-parity-reviewer.md|OPENCODE_CONFIG_DIR|agents/migration-parity-reviewer.md
agents/alegra-code-reviewer.md|OPENCODE_CONFIG_DIR|agents/alegra-code-reviewer.md
skills/monolith-to-micro-migration|OPENCODE_CONFIG_DIR|skills/monolith-to-micro-migration
skills/task-lifecycle|OPENCODE_CONFIG_DIR|skills/task-lifecycle
commands/migration-gap-analysis.md|OPENCODE_CONFIG_DIR|commands/migration-gap-analysis.md
bin/dh|LOCAL_BIN|dh
install|LOCAL_BIN|dh-install
global/AGENTS.md|OPENCODE_CONFIG_DIR|AGENTS.md
LINKS
}

# Recursos experimentales (closed data tools) — solo con --experimental-data-tools
list_experimental_links() {
  cat <<'LINKS'
agents/data-access.md|OPENCODE_CONFIG_DIR|agents/data-access.md
tools/dh_mysql_query.ts|OPENCODE_CONFIG_DIR|tools/dh_mysql_query.ts
tools/dh_mongodb_query.ts|OPENCODE_CONFIG_DIR|tools/dh_mongodb_query.ts
tools/dh_dynamodb_read.ts|OPENCODE_CONFIG_DIR|tools/dh_dynamodb_read.ts
tools/dh_dynamodb_write.ts|OPENCODE_CONFIG_DIR|tools/dh_dynamodb_write.ts
tools/dh_object_storage_read.ts|OPENCODE_CONFIG_DIR|tools/dh_object_storage_read.ts
commands/mysql-query.md|OPENCODE_CONFIG_DIR|commands/mysql-query.md
commands/mongodb-query.md|OPENCODE_CONFIG_DIR|commands/mongodb-query.md
commands/dynamodb-read.md|OPENCODE_CONFIG_DIR|commands/dynamodb-read.md
commands/dynamodb-write-confirmed.md|OPENCODE_CONFIG_DIR|commands/dynamodb-write-confirmed.md
commands/object-storage-read.md|OPENCODE_CONFIG_DIR|commands/object-storage-read.md
bin/dh-data-executor|LOCAL_BIN|dh-data-executor
LINKS
}

# Archivos gestionados como copias (managed copies, no symlinks)
list_managed_files() {
  cat <<'FILES'
agents/alegra-microservice-engineer.md|OPENCODE_CONFIG_DIR|agents/alegra-microservice-engineer.md
agents/alegra-microservice-test-engineer.md|OPENCODE_CONFIG_DIR|agents/alegra-microservice-test-engineer.md
agents/php-engineer.md|OPENCODE_CONFIG_DIR|agents/php-engineer.md
agents/migration-parity-reviewer.md|OPENCODE_CONFIG_DIR|agents/migration-parity-reviewer.md
agents/alegra-code-reviewer.md|OPENCODE_CONFIG_DIR|agents/alegra-code-reviewer.md
FILES
}
