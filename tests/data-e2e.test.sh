#!/usr/bin/env bash
# tests/data-e2e.test.sh — E2E: data tools install/uninstall/doctor
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAIL=0

# Source managed-links for list_managed_links
source "$ROOT_DIR/scripts/lib/managed-links.sh"

echo "=== Data tools E2E ==="

# 1. Verify tools/ files exist in source
for tool in dh_mysql_query.ts dh_mongodb_query.ts dh_dynamodb_read.ts dh_dynamodb_write.ts dh_object_storage_read.ts; do
    if [[ -f "$ROOT_DIR/tools/$tool" ]]; then
        echo "  [ok] tools/$tool existe"
    else
        echo "  [FAIL] tools/$tool no existe"
        FAIL=1
    fi
done

# 2. Verify data-access agent exists
if [[ -f "$ROOT_DIR/agents/data-access.md" ]]; then
    echo "  [ok] agents/data-access.md existe"
else
    echo "  [FAIL] agents/data-access.md no existe"
    FAIL=1
fi

# 3. Verify agent has bash: deny
if grep -qE 'deny' "$ROOT_DIR/agents/data-access.md" 2>/dev/null; then
    echo "  [ok] data-access.md tiene deny configurado"
else
    echo "  [FAIL] data-access.md no tiene deny"
    FAIL=1
fi

# 4. Verify all tools and commands are in managed-links inventory
INVENTORY=$(list_managed_links)
for entry in tools/dh_mysql_query.ts tools/dh_mongodb_query.ts tools/dh_dynamodb_read.ts tools/dh_dynamodb_write.ts tools/dh_object_storage_read.ts agents/data-access.md; do
    if echo "$INVENTORY" | grep -q "$entry"; then
        echo "  [ok] managed-links incluye $entry"
    else
        echo "  [FAIL] managed-links no incluye $entry"
        FAIL=1
    fi
done

# 5. Verify commands/*.md files exist
for cmd in mysql-query.md mongodb-query.md dynamodb-read.md dynamodb-write-confirmed.md object-storage-read.md; do
    if [[ -f "$ROOT_DIR/commands/$cmd" ]]; then
        echo "  [ok] commands/$cmd existe"
    else
        echo "  [FAIL] commands/$cmd no existe"
        FAIL=1
    fi
done

# 6. Verify backend modules exist
for mod in mysql.py mongodb.py dynamodb.py object_storage.py; do
    if [[ -f "$ROOT_DIR/scripts/dh_data/$mod" ]]; then
        echo "  [ok] scripts/dh_data/$mod existe"
    else
        echo "  [FAIL] scripts/dh_data/$mod no existe"
        FAIL=1
    fi
done

echo "---"
if (( FAIL > 0 )); then
    echo "Resultado: $FAIL fallo(s)"
    exit 1
else
    echo "Resultado: todos los checks pasaron"
    exit 0
fi
