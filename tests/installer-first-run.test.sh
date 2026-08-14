#!/usr/bin/env bash
# P0: Installer first-run — OAuth, PAT, error handling, exit codes
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STUBS="$TMP_DIR/stubs"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }
run_check() {
  local label=$1; shift
  set +e
  "$@" > "$TMP_DIR/${label// /_}.out" 2>&1; local rc=$?
  set -e
  printf '%s' "$rc"
}

setup_home() {
  local home=$1
  mkdir -p "$home/.nvm/versions/node/v24.0.0/bin" "$home/.config/daniel-harness/secrets/tunnels"
  echo '#!/bin/bash; echo v24.0.0' > "$home/.nvm/versions/node/v24.0.0/bin/node"
  chmod +x "$home/.nvm/versions/node/v24.0.0/bin/node"
  echo 'nvm() { :; }' > "$home/.nvm/nvm.sh"
  printf '%s\n' 'version: "1"' 'models:' '  - id: default' '    trust: trusted' '    allowArbitraryShell: false' '    allowedCapabilities: []' > "$home/.config/daniel-harness/config.yaml"
}

# --- Setup: stubs ---
printf '=== Setup ===\n'
mkdir -p "$STUBS"
cat > "$STUBS/sudo" <<'STUB'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
STUB
chmod +x "$STUBS/sudo"
for stub in apt-get dpkg curl node npm gentle-ai codegraph engram rtk dh gh aws unzip; do
  cat > "$STUBS/$stub" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUBS/$stub"
done
cat > "$STUBS/node" <<'STUB'
#!/bin/bash
echo "v24.0.0"
STUB
chmod +x "$STUBS/node"

export PATH="$STUBS:$PATH"
export DH_TEST_MODE=1
export DH_TRANSACTION_ALLOW_TMP=1

cat > "$STUBS/gentle-ai" <<'GENTLE'
#!/bin/bash
case "$1" in
  --version) echo "gentle-ai 2.3.0" ;;
  skill-registry|sync) exit 0 ;;
  doctor) echo "Status:  healthy" ;;
esac
GENTLE
chmod +x "$STUBS/gentle-ai"

bootstrap() {
  local profile=$1 home=$2
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    GITHUB_PERSONAL_ACCESS_TOKEN="ghp_fixture_not_real" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile "$profile"
}

doctor() {
  local home=$1 extra=$2
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    bash "$ROOT_DIR/scripts/doctor.sh" --profile core $extra
}

# --- Test 1: Doctor without --skip-oauth fails on auth-required ---
printf '\n=== Test 1: Doctor detects auth-required MCP ===\n'
setup_home "$TMP_DIR/home-auth"
cat > "$STUBS/opencode" <<'STUB'
#!/bin/bash
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug) echo "authentication required"; exit 0 ;; esac ;;
esac
exit 0
STUB
chmod +x "$STUBS/opencode"
# Bootstrap (passes --skip-oauth, should succeed)
bootstrap core "$TMP_DIR/home-auth" > /dev/null 2>&1
# Doctor without --skip-oauth should fail
rc=$(run_check "doctor-auth" doctor "$TMP_DIR/home-auth" "--strict")
[[ $rc -eq 1 ]] && pass "1a: doctor exits 1 with auth-required" || fail "1a: doctor exit $rc (expected 1)"
grep -q 'requiere autenticacion' "$TMP_DIR/doctor-auth.out" && pass "1b: doctor shows auth required" || fail "1b: doctor missing auth message"

# --- Test 2: Doctor with --skip-oauth passes despite auth-required ---
printf '\n=== Test 2: Doctor with --skip-oauth ===\n'
rc=$(run_check "doctor-skip-oauth" doctor "$TMP_DIR/home-auth" "--strict --skip-oauth")
[[ $rc -eq 0 ]] && pass "2a: doctor --skip-oauth exits 0" || fail "2a: doctor --skip-oauth exit $rc (expected 0)"

# --- Test 3: All connected (golden path) ---
printf '\n=== Test 3: All connected ===\n'
setup_home "$TMP_DIR/home-ok"
cat > "$STUBS/opencode" <<'STUB'
#!/bin/bash
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug) echo "connected"; exit 0 ;; esac ;;
esac
exit 0
STUB
chmod +x "$STUBS/opencode"
bootstrap core "$TMP_DIR/home-ok" > /dev/null 2>&1
rc=$(run_check "doctor-ok" doctor "$TMP_DIR/home-ok" "--strict")
[[ $rc -eq 0 ]] && pass "3a: doctor exits 0 with all connected" || fail "3a: doctor exit $rc (expected 0)"

# --- Test 4: 401 GitHub (tested via doctor, not bootstrap) ---
printf '\n=== Test 4: GitHub 401 ===\n'
setup_home "$TMP_DIR/home-gh401"
cat > "$STUBS/opencode" <<'STUB'
#!/bin/bash
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug)
    case "$3" in
      github) echo "401 Unauthorized"; exit 0 ;;
      *) echo "connected"; exit 0 ;;
    esac
  esac ;;
esac
exit 0
STUB
chmod +x "$STUBS/opencode"
bootstrap alegra "$TMP_DIR/home-gh401" > /dev/null 2>&1
rc=$(run_check "doctor-gh401" doctor "$TMP_DIR/home-gh401" "--profile alegra --strict")
[[ $rc -eq 1 ]] && pass "4a: doctor exits 1 with github 401" || fail "4a: doctor exit $rc (expected 1)"

# --- Summary ---
printf '\n========================================\n'
printf '  Installer first-run: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
