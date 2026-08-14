#!/usr/bin/env bash
# E2E: bootstrap real con stubs en HOME aislado
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)

cleanup_test_tmp() {
  if [[ "${DH_KEEP_TEST_TMP:-0}" == "1" ]]; then
    printf '%s\n' "TMP_DIR preservado: $TMP_DIR" >&2
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup_test_tmp EXIT

# Home aislado por perfil — evita contaminación entre fases
HOME_CORE="$TMP_DIR/home-core"
HOME_ALEGRA="$TMP_DIR/home-alegra"
HOME_MIGRATION="$TMP_DIR/home-migration"
HOME_FULL="$TMP_DIR/home-full"
CONFIG_TMP="$TMP_DIR/config"
STUBS="$TMP_DIR/stubs"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

run_check() {
  local label=$1; shift
  local safe_label=${label// /_}
  local stdout_file="$TMP_DIR/${safe_label}.stdout"
  local stderr_file="$TMP_DIR/${safe_label}.stderr"
  local rc_file="$TMP_DIR/${safe_label}.rc"

  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"; local rc=$?
  set -e

  printf '%s\n' "$rc" > "$rc_file"
  printf '%s' "$rc"
}

dump_failure() {
  local label=$1
  local home=$2
  local safe_label=${label// /_}
  local stdout_file="$TMP_DIR/${safe_label}.stdout"
  local stderr_file="$TMP_DIR/${safe_label}.stderr"

  printf '%s\n' "--- $label: stdout ---"
  cat "$stdout_file" 2>/dev/null || true

  printf '%s\n' "--- $label: stderr ---"
  cat "$stderr_file" 2>/dev/null || true

  printf '%s\n' "--- $label: journal sanitizado ---"
  local journal="$home/.config/daniel-harness/state/.bootstrap-journal.json"
  if [[ -f "$journal" ]]; then
    if ! jq '{
      journalVersion,
      phase,
      resources: [
        .resources[]? |
        {
          id,
          applyOrder,
          status,
          resourceType,
          existedBefore,
          hasTemp: (.tempPath != ""),
          hasBackup: (.backupPath != ""),
          hasOriginalSha: (.originalSha256 != ""),
          hasCandidateSha: (.candidateSha256 != "")
        }
      ]
    }' "$journal"; then
      printf '%s\n' '(journal inválido; contenido omitido)'
    fi
  else
    printf '%s\n' '(sin journal)'
  fi

  printf '%s\n' "--- $label: archivos relevantes ---"
  if [[ -d "$home/.config" ]]; then
    find "$home/.config" -maxdepth 4 -type f -o -type l 2>/dev/null |
      sort |
      sed "s#^$home#\$HOME#"
  else
    printf '%s\n' "(.config no existe)"
  fi
}

require_success() {
  local label=$1
  local command_rc=$2
  local home=$3

  if [[ $command_rc -ne 0 ]]; then
    printf '\n=== FAIL-FAST: %s (rc=%s) ===\n' "$label" "$command_rc"
    dump_failure "$label" "$home"
    exit 1
  fi
}

require_file() {
  local label=$1 path=$2
  if [[ ! -f "$path" ]]; then
    printf '=== FAIL-FAST: %s missing ===\n' "$label"
    printf '%s\n' "  path: $path"
    exit 1
  fi
}

# --- Setup: stubs (compartidos) ---
printf '=== Setup: stubs ===\n'
mkdir -p "$STUBS" "$HOME_CORE" "$HOME_ALEGRA" "$HOME_MIGRATION" "$HOME_FULL" "$CONFIG_TMP"
mkdir -p "$HOME_CORE/.nvm" "$HOME_ALEGRA/.nvm" "$HOME_MIGRATION/.nvm" "$HOME_FULL/.nvm"

cat > "$STUBS/sudo" <<'SUDO'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
SUDO
chmod +x "$STUBS/sudo"

cat > "$STUBS/apt-get" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUBS/apt-get"

cat > "$STUBS/dpkg" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]]; then echo "Status: install ok installed"; exit 0; fi
exit 0
EOF
chmod +x "$STUBS/dpkg"

create_nvm_curl_stub "$STUBS"

cat > "$STUBS/node" <<'NODE'
#!/bin/bash
echo "v24.0.0"; exit 0
NODE
chmod +x "$STUBS/node"

cat > "$STUBS/npm" <<'NPM'
#!/bin/bash
exit 0
NPM
chmod +x "$STUBS/npm"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug) echo "connected"; exit 0 ;; esac ;;
esac
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

cat > "$STUBS/gentle-ai" <<GENTLE
#!/bin/bash
case "\$1" in
  version) echo "gentle-ai 9.9.9 (stub)" ;;
  doctor) echo "Status:  healthy" ;;
  review) if [[ "\$2" == "mode" ]]; then echo "receipt-driven development: on (decided by default)"; fi ;;
  skill-registry) mkdir -p "$ROOT_DIR/.atl" 2>/dev/null; touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null; echo "ok" ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUBS/gentle-ai"

for tool in codegraph rtk engram; do
  cat > "$STUBS/$tool" <<EOF
#!/bin/bash
exit 0
EOF
  chmod +x "$STUBS/$tool"
done

cat > "$STUBS/dh" <<'DH'
#!/bin/bash
echo "dh stub"; exit 0
DH
chmod +x "$STUBS/dh"

mkdir -p "$CONFIG_TMP/daniel-harness/secrets/tunnels"
for tunnel in alegra-hopper alegra-production k-agencia-mysql k-agencia-mongodb k-agencia-garage; do
  printf 'echo %s tunnel stub\n' "$tunnel" > "$CONFIG_TMP/daniel-harness/secrets/tunnels/$tunnel.command"
  chmod 600 "$CONFIG_TMP/daniel-harness/secrets/tunnels/$tunnel.command"
done

# Use config.example.yaml as base but remove restricted models for E2E
# (doctor.sh flags agents without wildcard deny when restricted models exist)
python3 -c "
import yaml, json
from pathlib import Path
cfg = yaml.safe_load((Path('examples/config.example.yaml')).read_text())
cfg['models'] = [m for m in cfg['models'] if m.get('trust') != 'restricted']
from pathlib import Path
Path('$CONFIG_TMP/daniel-harness/config.yaml').write_text(yaml.dump(cfg))
" && pass "config fixture creada sin modelos restricted"
python3 -c "
import json, yaml, sys
from pathlib import Path
schema = json.loads((Path('schemas/config.schema.json')).read_text())
config = yaml.safe_load((Path('$CONFIG_TMP/daniel-harness/config.yaml')).read_text())
import jsonschema
jsonschema.validate(config, schema)
" && pass "config fixture valida contra schema" || fail "config fixture no valida"

for h in "$HOME_CORE" "$HOME_ALEGRA" "$HOME_MIGRATION" "$HOME_FULL"; do
  mkdir -p "$h/.config/daniel-harness/secrets/tunnels"
  cp "$CONFIG_TMP/daniel-harness/config.yaml" "$h/.config/daniel-harness/config.yaml"
  chmod 600 "$h/.config/daniel-harness/config.yaml"
done

export PATH="$STUBS:$PATH"
export DH_TEST_MODE=1
export DH_TRANSACTION_ALLOW_TMP=1

# Helper: bootstrap a profile with isolated HOME
bootstrap_profile() {
  local profile=$1 _label=$2 home=$3 skip_docker=${4:-false}
  local extra=""
  [[ "$skip_docker" == "true" ]] && extra="--skip-docker"
  local gh_token=""
  # Only core doesn't need GitHub; alegra/migration/full do
  if [[ "$profile" != "core" ]]; then
    gh_token="GITHUB_PERSONAL_ACCESS_TOKEN=ghp_fixture_not_real_123"
  fi
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    $gh_token \
    NAVI_MCP_URL="https://navi.example.com/mcp" \
    NAVI_OAUTH_CLIENT_ID="dummy-client-id" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile "$profile" $extra
}

# Helper: doctor a profile with isolated HOME
doctor_profile() {
  local profile=$1 _label=$2 home=$3
  local gh_token=""
  if [[ "$profile" != "core" ]]; then
    gh_token="GITHUB_PERSONAL_ACCESS_TOKEN=ghp_fixture_not_real_123"
  fi
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    $gh_token \
    NAVI_MCP_URL="https://navi.example.com/mcp" \
    NAVI_OAUTH_CLIENT_ID="dummy-client-id" \
    bash "$ROOT_DIR/scripts/doctor.sh" --profile "$profile" --strict
}

# Helper: check MCP exists in opencode.json for a profile
mcp_exists() {
  local home=$1 mcp=$2
  local oc_file="$home/.config/opencode/opencode.json"
  jq -e ".mcp | has(\"$mcp\")" "$oc_file" >/dev/null 2>&1
}

# Helper: get MCP list
mcp_list() {
  local home=$1
  local oc_file="$home/.config/opencode/opencode.json"
  jq -r '.mcp | keys[]' "$oc_file" 2>/dev/null | sort
}

# --- Phase 1: Bootstrap --profile core ---
printf '\n=== Phase 1: bootstrap --profile core ===\n'
rc=$(run_check "bootstrap-core" bootstrap_profile core core "$HOME_CORE")
require_success "bootstrap-core" "$rc" "$HOME_CORE"
pass "bootstrap core exit code 0"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-core.stdout" && pass "bootstrap core completed healthy" || {
  cat "$TMP_DIR/bootstrap-core.stdout"
  fail "bootstrap core not healthy"
  exit 1
}

OC_CORE="$HOME_CORE/.config/opencode/opencode.json"

# --- Phase 2: Validate opencode.json (core) ---
printf '\n=== Phase 2: opencode.json validation (core) ===\n'
jq empty "$OC_CORE" && pass "core opencode.json is valid JSON" || fail "core opencode.json is not valid JSON"
[[ $(jq 'has("mcp")' "$OC_CORE") == "true" ]] && pass "mcp section exists" || fail "mcp section missing"
[[ $(jq 'has("plugin")' "$OC_CORE") == "true" ]] && pass "plugin section exists" || fail "plugin section missing"
mcp_exists "$HOME_CORE" "codegraph" && pass "MCP codegraph in core" || fail "MCP codegraph missing"
mcp_exists "$HOME_CORE" "engram" && pass "MCP engram in core" || fail "MCP engram missing"
mcp_exists "$HOME_CORE" "linear" && fail "MCP linear should NOT be in core" || pass "MCP linear not in core"
mcp_exists "$HOME_CORE" "github" && fail "MCP github should NOT be in core" || pass "MCP github not in core"
mcp_exists "$HOME_CORE" "context7" && fail "MCP context7 should NOT be in core" || pass "MCP context7 not in core"
mcp_exists "$HOME_CORE" "wiki-alegra" && fail "MCP wiki-alegra should NOT be in core" || pass "MCP wiki-alegra not in core"
jq -e '[.mcp[] | has("disabledTools")] | any | not' "$OC_CORE" >/dev/null && pass "no MCP has disabledTools" || fail "some MCP still has disabledTools"
jq -e '.plugin[] | startswith("@dietrichgebert/ponytail")' "$OC_CORE" >/dev/null && pass "Ponytail plugin registered" || fail "Ponytail plugin missing"
jq -e '.mcp.codegraph.type == "local"' "$OC_CORE" >/dev/null && pass "codegraph is local" || fail "codegraph type mismatch"
jq -e '.mcp.engram.type == "local"' "$OC_CORE" >/dev/null && pass "engram is local" || fail "engram type mismatch"

# Schema compliance: no _managed, no oauth: true
jq -e '[.mcp[] | has("_managed")] | any | not' "$OC_CORE" >/dev/null && pass "no MCP has _managed field" || fail "some MCP still has _managed"
jq -e '[.mcp[] | select(.type == "remote") | .oauth == true] | any | not' "$OC_CORE" >/dev/null && pass "no remote MCP has oauth: true" || fail "some remote MCP has oauth: true"

# --- Phase 3: Agents and skills ---
printf '\n=== Phase 3: Agents and skills ===\n'
AGENT_DIR="$HOME_CORE/.config/opencode/agents"
for a in alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  f="$AGENT_DIR/$a.md"
  [[ -f "$f" ]] && pass "agent $a: file exists" || fail "agent $a missing"
  [[ ! -L "$f" ]] && pass "agent $a: not a symlink" || fail "agent $a: is still a symlink"
  AGENT_MODE=$(stat -c '%a' "$f" 2>/dev/null || echo "000")
  [[ "$AGENT_MODE" == "600" ]] && pass "agent $a: mode 600" || fail "agent $a: mode $AGENT_MODE"
done
# Verify managed state tracks agent hashes
AGENT_STATE="$HOME_CORE/.config/daniel-harness/state/opencode-managed.state"
[[ -f "$AGENT_STATE" ]] && pass "agent state file exists" || fail "agent state file missing"
for a in alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  grep -q "^agents/${a}.md|" "$AGENT_STATE" 2>/dev/null && pass "agent $a: tracked in state" || fail "agent $a: not tracked in state"
done
# Idempotence: second install should NOT re-copy
INSTALL_OUT2="$TMP_DIR/install-idempotent.out"
env PATH="$STUBS:$PATH" HOME="$HOME_CORE" XDG_CONFIG_HOME="$HOME_CORE/.config" \
  bash "$ROOT_DIR/scripts/install.sh" > "$INSTALL_OUT2" 2>&1
grep -q 'instalado:' "$INSTALL_OUT2" && fail "agent reinstall on idempotent run" || pass "agent idempotent: no reinstall"
for s in monolith-to-micro-migration task-lifecycle; do
  [[ -d "$HOME_CORE/.config/opencode/skills/$s" ]] && pass "skill $s" || fail "skill $s missing"
done
[[ -f "$HOME_CORE/.config/opencode/commands/migration-gap-analysis.md" ]] && pass "command migration-gap-analysis" || fail "command migration-gap-analysis missing"
[[ -L "$HOME_CORE/.local/bin/dh" ]] && pass "dh CLI linked" || fail "dh CLI missing"

# --- Phase 4: Doctor --profile core --strict ---
printf '\n=== Phase 4: doctor --profile core --strict ===\n'
rc=$(run_check "doctor-core" doctor_profile core core "$HOME_CORE")
[[ $rc -eq 0 ]] && pass "doctor core exit code 0" || fail "doctor core exit code $rc"
grep -q 'Resumen: 0 crítico(s)' "$TMP_DIR/doctor-core.stdout" && pass "doctor --profile core --strict passed" || {
  cat "$TMP_DIR/doctor-core.stdout"
  fail "doctor reported criticals"
}

# --- Phase 5: Idempotence (second core bootstrap) ---
printf '\n=== Phase 5: Idempotence ===\n'
CORE_OC="$HOME_CORE/.config/opencode/opencode.json"
FIRST_HASH=$(sha256sum "$CORE_OC" 2>/dev/null | cut -d' ' -f1 || echo none)
BACKUPS_BEFORE=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
rc=$(run_check "bootstrap-idempotent" bootstrap_profile core core "$HOME_CORE")
[[ $rc -eq 0 ]] && pass "second bootstrap exit code 0" || fail "second bootstrap exit code $rc"
SECOND_HASH=$(sha256sum "$CORE_OC" 2>/dev/null | cut -d' ' -f1 || echo none)
[[ "$FIRST_HASH" == "$SECOND_HASH" ]] && pass "second bootstrap is idempotent (opencode.json unchanged)" || fail "second bootstrap modified opencode.json"
BACKUPS_AFTER=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
[[ "$BACKUPS_AFTER" -eq "$BACKUPS_BEFORE" ]] && pass "no new backups created on second run" || fail "second bootstrap created unnecessary backups"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-idempotent.stdout" && pass "second bootstrap healthy" || fail "second bootstrap failed"

# --- Phase 5c: Core → alegra transition on same HOME ---
printf '\n=== Phase 5c: Core → alegra transition ===\n'
TRANSITION_HOME="$TMP_DIR/home-transition"
mkdir -p "$TRANSITION_HOME/.config/daniel-harness/secrets/tunnels" "$TRANSITION_HOME/.nvm/versions/node/v24.0.0/bin"
cp "$CONFIG_TMP/daniel-harness/config.yaml" "$TRANSITION_HOME/.config/daniel-harness/config.yaml"
echo 'nvm() { :; }' > "$TRANSITION_HOME/.nvm/nvm.sh"
echo '#!/bin/bash; echo v24.0.0' > "$TRANSITION_HOME/.nvm/versions/node/v24.0.0/bin/node"
chmod +x "$TRANSITION_HOME/.nvm/versions/node/v24.0.0/bin/node"
rc=$(run_check "transition-core" bootstrap_profile core core "$TRANSITION_HOME")
[[ $rc -eq 0 ]] && pass "transition: core bootstrap ok" || {
  dump_failure "transition-core" "$TRANSITION_HOME"
  fail "transition: core bootstrap failed"
  rm -rf "$TRANSITION_HOME"
  exit 1
}
# Pre-compute alegra MCPs (we'll validate after transition)
TRANSITION_OC="$TRANSITION_HOME/.config/opencode/opencode.json"
# Bootstrap alegra on same HOME
rc=$(run_check "transition-alegra" bootstrap_profile alegra alegra "$TRANSITION_HOME")
[[ $rc -eq 0 ]] && pass "transition: alegra bootstrap ok" || {
  dump_failure "transition-alegra" "$TRANSITION_HOME"
  fail "transition: alegra bootstrap failed"
  rm -rf "$TRANSITION_HOME"
  exit 1
}
# Verify alegra MCPs present (more than core)
TRANSITION_MCPS=$(jq -r '.mcp | keys[]' "$TRANSITION_OC" 2>/dev/null | sort)
for mcp in codegraph engram linear context7 wiki-alegra github; do
  echo "$TRANSITION_MCPS" | grep -qxF "$mcp" && pass "transition: MCP $mcp present" || fail "transition: MCP $mcp missing"
done
# Verify state file tracks all alegra MCPs
STATE_FILE="$TRANSITION_HOME/.config/daniel-harness/state/opencode-managed.json"
for mcp in codegraph engram linear context7 wiki-alegra github; do
  jq -e --arg n "$mcp" '.mcps | has($n)' "$STATE_FILE" >/dev/null && pass "transition: state has $mcp" || fail "transition: state missing $mcp"
done
# Verify doctor --profile alegra --strict passes
rc=$(run_check "transition-doctor" doctor_profile alegra alegra "$TRANSITION_HOME")
[[ $rc -eq 0 ]] && pass "transition: doctor alegra passes" || {
  dump_failure "transition-doctor" "$TRANSITION_HOME"
  fail "transition: doctor alegra failed"
}
rm -rf "$TRANSITION_HOME"

# --- Phase 6: Profile manifest validation ---
printf '\n=== Phase 6: Profile manifest validation ===\n'
for profile in core alegra migration full; do
  awk -v p="$profile" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { found=1; exit }
  ' "$ROOT_DIR/bootstrap/manifest.yaml" && pass "profile $profile exists in manifest" || fail "profile $profile missing from manifest"
done

# --- Phase 7: Bootstrap --profile alegra (HOME aislado) ---
printf '\n=== Phase 7: bootstrap --profile alegra ===\n'
rc=$(run_check "bootstrap-alegra" bootstrap_profile alegra alegra "$HOME_ALEGRA")
[[ $rc -eq 0 ]] && pass "bootstrap alegra exit code 0" || fail "bootstrap alegra exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-alegra.stdout" && pass "bootstrap alegra completed healthy" || {
  dump_failure "bootstrap-alegra" "$HOME_ALEGRA"
  fail "bootstrap alegra not healthy"
}

OC_ALEGRA="$HOME_ALEGRA/.config/opencode/opencode.json"

# Verify exact MCP set for alegra: codegraph, engram, linear, context7, wiki-alegra, github
printf '\n=== Phase 7b: MCP set validation (alegra) ===\n'
ALEGRA_MCPS=$(mcp_list "$HOME_ALEGRA")
for mcp in codegraph engram linear context7 wiki-alegra github; do
  echo "$ALEGRA_MCPS" | grep -qxF "$mcp" && pass "alegra MCP $mcp" || fail "alegra MCP $mcp missing"
done
for mcp in sentry navi; do
  echo "$ALEGRA_MCPS" | grep -qxF "$mcp" && fail "alegra should NOT have MCP $mcp" || pass "alegra correctly lacks MCP $mcp"
done

# --- Phase 7c: Schema and OAuth assertions (alegra) ---
printf '\n=== Phase 7c: Schema and OAuth validation (alegra) ===\n'
jq -e \
  '.mcp.github.headers.Authorization |
   test("^(Bearer )?(\\{env:GITHUB_PERSONAL_ACCESS_TOKEN\\}|\\{file:)")' \
  "$OC_ALEGRA" >/dev/null &&
  pass "alegra: github Authorization valida" ||
  fail "alegra: github Authorization tiene un formato inesperado"
jq -e '.mcp.github.headers["X-MCP-Toolsets"] == "repos,pull_requests,issues"' "$OC_ALEGRA" >/dev/null && pass "alegra: github X-MCP-Toolsets exact" || fail "alegra: github X-MCP-Toolsets mismatch"
jq -e '.mcp.github.oauth == false' "$OC_ALEGRA" >/dev/null && pass "alegra: github oauth false" || fail "alegra: github oauth not false"
jq -e '.mcp.linear.oauth == {}' "$OC_ALEGRA" >/dev/null && pass "alegra: linear oauth {}" || fail "alegra: linear oauth not object"
jq -e '.mcp.context7 | has("oauth") | not' "$OC_ALEGRA" >/dev/null && pass "alegra: context7 no oauth" || fail "alegra: context7 has unexpected oauth"
jq -e '[.mcp[] | has("_managed")] | any | not' "$OC_ALEGRA" >/dev/null && pass "alegra: no MCP has _managed" || fail "alegra: some MCP has _managed"
jq -e '[.mcp[] | select(.type == "remote") | .oauth == true] | any | not' "$OC_ALEGRA" >/dev/null && pass "alegra: no remote MCP has oauth: true" || fail "alegra: some remote MCP has oauth: true"
jq -e '.plugin[] == "@dietrichgebert/ponytail@4.8.4"' "$OC_ALEGRA" >/dev/null && pass "alegra: ponytail exact version" || fail "alegra: ponytail version mismatch"
ALEGRA_STATE="$HOME_ALEGRA/.config/daniel-harness/state/opencode-managed.json"
[[ -f "$ALEGRA_STATE" ]] && pass "alegra: state file exists" || fail "alegra: state file missing"
STAT_MODE=$(stat -c '%a' "$ALEGRA_STATE" 2>/dev/null || echo "000")
[[ "$STAT_MODE" == "600" ]] && pass "alegra: state file mode 600" || fail "alegra: state file mode is $STAT_MODE"

# --- Phase 8: Bootstrap --profile migration --skip-docker (HOME aislado) ---
printf '\n=== Phase 8: bootstrap --profile migration --skip-docker ===\n'
rc=$(run_check "bootstrap-migration" bootstrap_profile migration migration "$HOME_MIGRATION" true)
[[ $rc -eq 0 ]] && pass "bootstrap migration --skip-docker exit code 0" || fail "bootstrap migration --skip-docker exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-migration.stdout" && pass "bootstrap migration completed healthy" || {
  dump_failure "bootstrap-migration" "$HOME_MIGRATION"
  fail "bootstrap migration not healthy"
}
grep -q 'Docker omitido' "$TMP_DIR/bootstrap-migration.stdout" && pass "migration --skip-docker respected" || fail "migration did not skip docker"

OC_MIGRATION="$HOME_MIGRATION/.config/opencode/opencode.json"

# Verify exact MCP set for migration: heredados de alegra + navi
printf '\n=== Phase 8b: MCP set validation (migration) ===\n'
MIGRATION_MCPS=$(mcp_list "$HOME_MIGRATION")
for mcp in codegraph engram linear context7 wiki-alegra github navi; do
  echo "$MIGRATION_MCPS" | grep -qxF "$mcp" && pass "migration MCP $mcp" || fail "migration MCP $mcp missing"
done
echo "$MIGRATION_MCPS" | grep -qxF "sentry" && fail "migration should NOT have MCP sentry" || pass "migration correctly lacks sentry"

# --- Phase 9: Bootstrap --profile full (HOME aislado) ---
printf '\n=== Phase 9: bootstrap --profile full ===\n'
rc=$(run_check "bootstrap-full" bootstrap_profile full full "$HOME_FULL")
[[ $rc -eq 0 ]] && pass "bootstrap full exit code 0" || fail "bootstrap full exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-full.stdout" && pass "bootstrap full completed healthy" || {
  dump_failure "bootstrap-full" "$HOME_FULL"
  fail "bootstrap full not healthy"
  exit 1
}

OC_FULL="$HOME_FULL/.config/opencode/opencode.json"

# Verify exact MCP set for full: heredados de alegra + navi + sentry
printf '\n=== Phase 9b: MCP set validation (full) ===\n'
FULL_MCPS=$(mcp_list "$HOME_FULL")
for mcp in codegraph engram linear context7 wiki-alegra github navi sentry; do
  echo "$FULL_MCPS" | grep -qxF "$mcp" && pass "full MCP $mcp" || fail "full MCP $mcp missing"
done
# no extra MCPs beyond the expected set
EXPECTED_FULL="codegraph engram linear context7 wiki-alegra github navi sentry"
for mcp in $FULL_MCPS; do
  echo "$EXPECTED_FULL" | grep -qwF "$mcp" && pass "full MCP $mcp is in expected set" || fail "full has unexpected MCP $mcp"
done

# --- Phase 10: Invalid JSON rollback (sobre HOME core para evitar contaminar perfiles) ---
printf '\n=== Phase 10: Invalid JSON rollback ===\n'
BACKUPS_BEFORE_RB=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
printf 'INVALID JSON' > "$OC_CORE"
rc=$(run_check "bootstrap-rollback" env PATH="$STUBS:$PATH" HOME="$HOME_CORE" XDG_CONFIG_HOME="$HOME_CORE/.config" NVM_DIR="$HOME_CORE/.nvm" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core)
[[ $rc -eq 1 ]] && pass "bootstrap with invalid JSON exits code 1" || fail "bootstrap with invalid JSON exit code $rc (expected 1)"
BACKUPS_AFTER_RB=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
[[ $BACKUPS_AFTER_RB -eq $((BACKUPS_BEFORE_RB + 1)) ]] && pass "backup created (before=$BACKUPS_BEFORE_RB after=$BACKUPS_AFTER_RB)" || fail "backup count mismatch expected +1: before=$BACKUPS_BEFORE_RB after=$BACKUPS_AFTER_RB"

# --- Phase 11: Doctor live check (auth-required sobre alegra con linear) ---
printf '\n=== Phase 11: Doctor MCP live check (alegra profile, linear auth-only) ===\n'
HOME_ALEGRA_11="$TMP_DIR/home-alegra-11"
mkdir -p "$HOME_ALEGRA_11/.config/daniel-harness/secrets/tunnels" "$HOME_ALEGRA_11/.nvm"
cp "$CONFIG_TMP/daniel-harness/config.yaml" "$HOME_ALEGRA_11/.config/daniel-harness/config.yaml"
env PATH="$STUBS:$PATH" HOME="$HOME_ALEGRA_11" XDG_CONFIG_HOME="$HOME_ALEGRA_11/.config" NVM_DIR="$HOME_ALEGRA_11/.nvm" \
  GITHUB_PERSONAL_ACCESS_TOKEN="ghp_fixture_not_real_123" \
  NAVI_MCP_URL="https://navi.example.com/mcp" \
  NAVI_OAUTH_CLIENT_ID="dummy-client-id" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$TMP_DIR/bootstrap-alegra-11.stdout" 2>"$TMP_DIR/bootstrap-alegra-11.stderr" && \
  pass "phase 11: alegra bootstrap ok" || {
    dump_failure "bootstrap-alegra-11" "$HOME_ALEGRA_11"
    fail "phase 11: alegra bootstrap failed"
  }
# OpenCode stub: solo linear requiere auth, los demas connected
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug)
    case "$3" in
      linear) echo "Authentication required"; exit 1 ;;
      *) echo "connected"; exit 0 ;;
    esac
  esac ;;
esac
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

rc=$(run_check "doctor-auth" env PATH="$STUBS:$PATH" HOME="$HOME_ALEGRA_11" XDG_CONFIG_HOME="$HOME_ALEGRA_11/.config" NVM_DIR="$HOME_ALEGRA_11/.nvm" bash "$ROOT_DIR/scripts/doctor.sh" --profile alegra --strict)
[[ $rc -eq 1 ]] && pass "phase 11: doctor with auth-required linear exits 1" || fail "phase 11: doctor exit code $rc (expected 1)"
if grep -q 'requiere autenticacion' "$TMP_DIR/doctor-auth.stdout" "$TMP_DIR/doctor-auth.stderr"; then
  pass "phase 11: doctor detects auth-required MCP"
else
  dump_failure "doctor-auth" "$HOME_ALEGRA_11"
  fail "phase 11: doctor did not flag auth-required MCP"
fi

# Restore opencode stub
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "$1" in
  --version) echo "opencode 1.18.18"; exit 0 ;;
  agent) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp) case "$2" in debug) echo "connected"; exit 0 ;; esac ;;
esac
exit 0
OPENCODE
chmod +x "$STUBS/opencode"
rm -rf "$HOME_ALEGRA_11"

# --- Summary ---
printf '\n========================================\n'
printf '  Resultados: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
