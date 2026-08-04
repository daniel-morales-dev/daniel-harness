#!/usr/bin/env bash
# tests/launcher.test.sh — Tests for bin/dh-data-executor
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

LAUNCHER="$ROOT_DIR/bin/dh-data-executor"

echo "=== Test 1: Launcher existe y es ejecutable ==="
[[ -f "$LAUNCHER" ]] && pass "launcher exists" || fail "launcher missing"
[[ -x "$LAUNCHER" ]] && pass "launcher is executable" || fail "launcher not executable"

echo "=== Test 2: Launcher funciona desde directorio externo ==="
# Run from /tmp to verify it resolves its own path
echo '{"tool":"mysql-query","profile":"nope","operation":"query","params":{"sql":"SELECT 1"}}' | (
  cd /tmp
  RC=0
  "$LAUNCHER" > "$TMP_DIR/launcher.out" 2>&1 || RC=$?
  grep -q '"error"' "$TMP_DIR/launcher.out" && pass "launcher works from external dir" || fail "launcher failed from external dir"
)

echo "=== Test 3: Exit code 1 (runtime error) ==="
echo '{"tool":"mysql-query","profile":"missing","operation":"query","params":{"sql":"SELECT 1"}}' | "$LAUNCHER" > /dev/null 2>&1 && RC=$? || RC=$?
[[ $RC -eq 1 ]] && pass "exit code 1 for profile not found" || fail "expected 1 got $RC"

# Create test config directory with connections.yaml
TEST_CFG="$TMP_DIR/test-cfg"
mkdir -p "$TEST_CFG/secrets/mysql"
cat > "$TEST_CFG/connections.yaml" << 'YAML'
version: "1"
profiles:
  - id: test
    type: mysql
    readOnly: true
    host: 127.0.0.1
    port: 3306
    credentialsRef: secrets/mysql/test.cnf
YAML
chmod 600 "$TEST_CFG/connections.yaml"
echo "[client] password=test" > "$TEST_CFG/secrets/mysql/test.cnf"
chmod 600 "$TEST_CFG/secrets/mysql/test.cnf"

echo "=== Test 4: Exit code 2 (policy violation) ==="
echo '{"tool":"mysql-query","profile":"test","operation":"query","params":{"sql":"DELETE FROM x"}}' | \
  DANIEL_HARNESS_CONFIG_DIR="$TEST_CFG" "$LAUNCHER" > /dev/null 2>&1 && RC=$? || RC=$?
[[ $RC -eq 2 ]] && pass "exit code 2 for policy violation" || fail "expected 2 got $RC"

echo "=== Test 5: Exit code 2 (unknown tool) ==="
echo '{"tool":"unknown","profile":"test","operation":"query","params":{}}' | \
  DANIEL_HARNESS_CONFIG_DIR="$TEST_CFG" "$LAUNCHER" > /dev/null 2>&1 && RC=$? || RC=$?
[[ $RC -eq 2 ]] && pass "exit code 2 for unknown tool" || fail "expected 2 got $RC"

echo "=== Test 6: Exit code 1 (invalid JSON) ==="
echo 'not-json' | "$LAUNCHER" > /dev/null 2>&1 && RC=$? || RC=$?
[[ $RC -eq 1 ]] && pass "exit code 1 for invalid JSON" || fail "expected 1 got $RC"

echo "=== Test 7: Imports sin sys.path manual ==="
python3 -c "
import sys
# Remove any manual path insertions that tests do
sys.path = [p for p in sys.path if 'scripts' not in p and 'dh_data' not in p]
# Verify dh_data is importable only via PYTHONPATH set by launcher
import subprocess
result = subprocess.run(
    ['$LAUNCHER'],
    input='{\"tool\":\"mysql-query\",\"profile\":\"x\",\"operation\":\"query\",\"params\":{\"sql\":\"SELECT 1\"}}',
    capture_output=True, text=True, timeout=10,
    env={**__import__(\"os\").environ}
)
# Should fail gracefully (no config), not with ImportError
assert 'ImportError' not in result.stderr, f'Import error in stderr: {result.stderr}'
" && pass "no ImportError with clean PYTHONPATH" || fail "ImportError detected"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
