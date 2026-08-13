#!/usr/bin/env bash
# Contrato de compatibilidad probado contra la CLI OpenCode 1.18.18.
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

setup_fixture() {
  local name=$1
  local home="$TMP_DIR/$name/home"
  local stubs="$TMP_DIR/$name/stubs"
  mkdir -p "$home/.nvm/versions/node/v24.0.0/bin" "$home/.config/daniel-harness/secrets/tunnels" "$stubs"
  printf '%s\n' 'nvm() { :; }' > "$home/.nvm/nvm.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo v24.0.0' > "$home/.nvm/versions/node/v24.0.0/bin/node"
  chmod +x "$home/.nvm/versions/node/v24.0.0/bin/node"
  printf '%s\n' 'version: "1"' 'models:' '  - id: default' '    trust: trusted' '    allowArbitraryShell: false' '    allowedCapabilities: []' > "$home/.config/daniel-harness/config.yaml"
  for tool in sudo apt-get dpkg curl node npm codegraph engram rtk dh; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$stubs/$tool"
    chmod +x "$stubs/$tool"
  done
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in' '  --version) printf "%s\\n" "gentle-ai 2.3.0" ;;' '  skill-registry|sync) exit 0 ;;' '  doctor) printf "%s\\n" "Status:  healthy" ;;' 'esac' > "$stubs/gentle-ai"
  chmod +x "$stubs/gentle-ai"
  printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == "-n" && "${2:-}" == "true" ]] && exit 0' '[[ "${1:-}" == "-v" ]] && exit 0' 'exec "$@"' > "$stubs/sudo"
  chmod +x "$stubs/sudo"
  printf '%s\n' "$home|$stubs"
}

write_opencode_stub() {
  local stubs=$1 version=$2 missing=${3:-}
  cat > "$stubs/opencode" <<STUB
#!/usr/bin/env bash
case "\$1:\${2:-}:\${3:-}" in
  --version::) printf '%s\\n' '$version'; exit 0 ;;
  agent:list:--help) [[ '$missing' == agent-list ]] && exit 64; exit 0 ;;
  mcp::--help) [[ '$missing' == mcp ]] && exit 64; exit 0 ;;
  mcp:debug:--help) [[ '$missing' == mcp-debug ]] && exit 64; exit 0 ;;
  mcp:auth:--help) [[ '$missing' == mcp-auth ]] && exit 64; exit 0 ;;
  debug:config:--help) [[ '$missing' == debug-config ]] && exit 64; exit 0 ;;
  agent:list:*) printf '%s\\n' 'alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer'; exit 0 ;;
  mcp:debug:*) printf '%s\\n' connected; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$stubs/opencode"
}

run_bootstrap() {
  local name=$1 home=$2 stubs=$3
  set +e
  env PATH="$stubs:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/$name.out" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

expect_success() {
  local label=$1 version=$2
  local fixture home stubs rc
  fixture=$(setup_fixture "$label")
  IFS='|' read -r home stubs <<< "$fixture"
  write_opencode_stub "$stubs" "$version"
  rc=$(run_bootstrap "$label" "$home" "$stubs")
  [[ "$rc" == 0 ]] && pass "$label acepta $version" || fail "$label devuelve $rc"
}

expect_failure() {
  local label=$1 version=$2 missing=${3:-}
  local fixture home stubs rc
  fixture=$(setup_fixture "$label")
  IFS='|' read -r home stubs <<< "$fixture"
  write_opencode_stub "$stubs" "$version" "$missing"
  rc=$(run_bootstrap "$label" "$home" "$stubs")
  [[ "$rc" == 1 ]] && pass "$label falla cerrado" || fail "$label devuelve $rc"
}

printf '=== Version parsing ===\n'
expect_success plain 1.18.18
expect_success prefixed v1.18.18
expect_success prerelease 1.18.18-beta.1
expect_success large-components 1.118.103
expect_success extra-text 'OpenCode 1.18.18 build'
expect_failure invalid-version invalid
expect_failure below-minimum 1.18.17

printf '\n=== Required capabilities ===\n'
expect_failure missing-agent-list 1.18.18 agent-list
expect_failure missing-mcp-auth 1.18.18 mcp-auth
expect_failure missing-mcp-debug 1.18.18 mcp-debug
expect_failure missing-debug-config 1.18.18 debug-config

printf '\n=== Resultados: %d pasaron, %d fallaron ===\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
