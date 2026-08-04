#!/usr/bin/env bash
# tests/data-e2e.test.sh — E2E: data tools source verification
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAIL=0

source "$ROOT_DIR/scripts/lib/managed-links.sh"

echo "=== Data tools source verification ==="

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

# 3. Verify agent has mode: subagent and permission wildcard
if grep -qE 'mode: subagent' "$ROOT_DIR/agents/data-access.md" 2>/dev/null; then
    echo "  [ok] data-access.md mode: subagent"
else
    echo "  [FAIL] data-access.md sin mode: subagent"
    FAIL=1
fi
if grep -qE '"*": deny' "$ROOT_DIR/agents/data-access.md" 2>/dev/null; then
    echo "  [ok] data-access.md wildcard deny"
else
    echo "  [FAIL] data-access.md sin wildcard deny"
    FAIL=1
fi
ALLOW_COUNT=$(grep -cE 'dh_\w+: allow' "$ROOT_DIR/agents/data-access.md" 2>/dev/null || echo 0)
if [[ "$ALLOW_COUNT" -eq 5 ]]; then
    echo "  [ok] data-access.md: 5 custom tools allow"
else
    echo "  [FAIL] data-access.md: expected 5 tools allow, got $ALLOW_COUNT"
    FAIL=1
fi

# 4. Verify all tools and commands are in experimental-links inventory
INVENTORY=$(list_experimental_links)
for entry in tools/dh_mysql_query.ts tools/dh_mongodb_query.ts tools/dh_dynamodb_read.ts tools/dh_dynamodb_write.ts tools/dh_object_storage_read.ts agents/data-access.md; do
    if echo "$INVENTORY" | grep -q "$entry"; then
        echo "  [ok] list_experimental_links incluye $entry"
    else
        echo "  [FAIL] list_experimental_links no incluye $entry"
        FAIL=1
    fi
done

# 5. Verify data tools NOT in stable inventory
STABLE=$(list_managed_links)
for entry in tools/dh_mysql_query.ts tools/dh_mongodb_query.ts tools/dh_dynamodb_read.ts tools/dh_dynamodb_write.ts tools/dh_object_storage_read.ts agents/data-access.md bin/dh-data-executor; do
    if echo "$STABLE" | grep -q "$entry"; then
        echo "  [FAIL] $entry debería estar en list_experimental_links, no en list_managed_links"
        FAIL=1
    else
        echo "  [ok] $entry correctamente excluido de list_managed_links"
    fi
done

# 6. Verify commands/*.md files exist
for cmd in mysql-query.md mongodb-query.md dynamodb-read.md dynamodb-write-confirmed.md object-storage-read.md; do
    if [[ -f "$ROOT_DIR/commands/$cmd" ]]; then
        echo "  [ok] commands/$cmd existe"
    else
        echo "  [FAIL] commands/$cmd no existe"
        FAIL=1
    fi
done

# 7. Verify backend modules exist
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
